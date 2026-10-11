import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../models/report_point.dart';
import '../../providers/map_layer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/report_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/map_tile_layer.dart';

enum _SearchMode { calle, reporte }

/// Pestaña "Rutas": buscá un destino (una sola dirección) y la app calcula
/// el camino desde tu ubicación actual. Si además indicás un punto de
/// partida propio, calcula el camino entre esas dos direcciones, igual
/// que antes.
class RouteDistanceScreen extends StatefulWidget {
  /// Punto que el usuario marcó tocando el mapa en la pestaña "Mapa", si
  /// llegó a esta pantalla de esa forma. Al entrar, se le pregunta al
  /// usuario si quiere usarlo como destino (ruta B, saliendo desde su
  /// ubicación actual) o como punto de partida (ruta A, escribiendo el
  /// destino a mano).
  final LatLng? initialMarkedPoint;

  const RouteDistanceScreen({super.key, this.initialMarkedPoint});

  @override
  State<RouteDistanceScreen> createState() => _RouteDistanceScreenState();
}

class _RouteDistanceScreenState extends State<RouteDistanceScreen> {
  static const _myLocationLabel = 'Mi ubicación actual';

  final _geocodingService = GeocodingService();
  final _routingService = RoutingService();
  final _locationService = LocationService();
  final _reportService = ReportService();
  final _mapController = MapController();

  final _destinoController = TextEditingController();
  final _origenController = TextEditingController();

  final AudioPlayer _alertPlayer = AudioPlayer();
  final Set<String> _alertedReports = {};

  Timer? _debounceDestino;
  Timer? _debounceOrigen;

  List<AddressSuggestion> _resultsDestino = [];
  List<AddressSuggestion> _resultsOrigen = [];
  bool _searchingDestino = false;
  bool _searchingOrigen = false;

  AddressSuggestion? _destinoPoint;
  AddressSuggestion? _origenPoint;
  AddressSuggestion? _resolvedOrigin; // el que efectivamente se usó en la ruta

  bool _showOrigenField = false;
  _SearchMode _searchMode = _SearchMode.calle;

  final List<AddressSuggestion> _recientes = [];
  List<ReportPoint>? _allReportsCache;

  RouteResult? _route;
  bool _loadingRoute = false;
  String _profile = 'driving'; // 'driving' | 'cycling' | 'walking'
  //Boton de iniciar recorrido
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _livePosition;

  // Reportes que están cerca del recorrido calculado.
  List<ReportPoint> _routeReports = [];

  String? _errorMessage;

  LatLng? _cachedCurrentPosition;
  bool _loadingInitialLocation = true;

  @override
  void initState() {
    super.initState();
    _initializeMapLocation();
    if (widget.initialMarkedPoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _askHowToUseMarkedPoint(widget.initialMarkedPoint!);
      });
    }
  }

  Future<void> _initializeMapLocation() async {
    await _getCurrentLatLng();
    if (!mounted) return;
    setState(() => _loadingInitialLocation = false);
  }

  /// Le pregunta al usuario cómo quiere usar un punto que marcó tocando
  /// el mapa: como destino (ruta B, saliendo desde su ubicación actual)
  /// o como punto de partida (ruta A, escribiendo el destino a mano).
  Future<void> _askHowToUseMarkedPoint(LatLng point) async {
    if (!mounted) return;
    final useAsDestino = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Marcaste un punto en el mapa',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '¿Cómo lo querés usar?',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Como destino (ruta B)'),
                subtitle: const Text('Saliendo desde mi ubicación actual'),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.trip_origin),
                title: const Text('Como punto de partida (ruta A)'),
                subtitle: const Text('Voy a escribir el destino'),
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (useAsDestino == null || !mounted) return;

    setState(() {
      _errorMessage = null;
      if (useAsDestino) {
        _searchingDestino = true;
      } else {
        _searchingOrigen = true;
      }
    });

    // Geocodificación inversa para mostrar una dirección legible en vez
    // de coordenadas; si falla, se usa una etiqueta genérica.
    final resolved =
        await _geocodingService.reverseGeocode(
          point.latitude,
          point.longitude,
        ) ??
        AddressSuggestion(
          displayName: 'Punto marcado en el mapa',
          latitude: point.latitude,
          longitude: point.longitude,
        );

    if (!mounted) return;

    if (useAsDestino) {
      setState(() => _searchingDestino = false);
      _selectDestinoFromMap(resolved);
    } else {
      setState(() {
        _searchingOrigen = false;
        _showOrigenField = true;
      });
      _selectOrigenFromMap(resolved);
    }
  }

  /// Igual que [_selectDestino], pero sin dar por sentado que el usuario
  /// estaba escribiendo en el campo (el punto viene del mapa).
  void _selectDestinoFromMap(AddressSuggestion suggestion) {
    setState(() {
      _destinoPoint = suggestion;
      _destinoController.text = suggestion.displayName;
      _resultsDestino = [];
      _route = null;
    });
    _addRecent(suggestion);
    _tryComputeRoute();
  }

  /// Igual que [_selectOrigen], pero sin dar por sentado que el usuario
  /// estaba escribiendo en el campo (el punto viene del mapa).
  void _selectOrigenFromMap(AddressSuggestion suggestion) {
    setState(() {
      _origenPoint = suggestion;
      _origenController.text = suggestion.displayName;
      _resultsOrigen = [];
      _route = null;
    });
    _addRecent(suggestion);
    if (_destinoPoint != null) _tryComputeRoute();
  }

  Future<LatLng?> _getCurrentLatLng() async {
    if (_cachedCurrentPosition != null) return _cachedCurrentPosition;
    try {
      final position = await _locationService.getCurrentPosition();
      _cachedCurrentPosition = LatLng(position.latitude, position.longitude);
      return _cachedCurrentPosition;
    } catch (_) {
      return null;
    }
  }

  Future<List<ReportPoint>> _getAllReports() async {
    _allReportsCache ??= await _reportService.getAllReports();
    return _allReportsCache!;
  }

  // Detecta los reportes en el recorrido
  List<ReportPoint> _findReportsAlongRoute(
    List<LatLng> routePoints,
    List<ReportPoint> reports,
  ) {
    const double distanceLimitMeters = 80;

    return reports.where((report) {
      return routePoints.any((point) {
        final distance = const Distance().as(
          LengthUnit.Meter,
          point,
          LatLng(report.latitude, report.longitude),
        );

        return distance <= distanceLimitMeters;
      });
    }).toList();
  }

  void _onChangedDestino(String value) {
    _destinoPoint = null;
    _route = null;
    _debounceDestino?.cancel();
    _debounceDestino = Timer(
      const Duration(milliseconds: 500),
      () => _search(value, isDestino: true),
    );
    setState(() {});
  }

  void _onChangedOrigen(String value) {
    _origenPoint = null;
    _route = null;
    _debounceOrigen?.cancel();
    _debounceOrigen = Timer(
      const Duration(milliseconds: 500),
      () => _search(value, isDestino: false),
    );
    setState(() {});
  }

  Future<void> _search(String query, {required bool isDestino}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      setState(() {
        if (isDestino) {
          _resultsDestino = [];
        } else {
          _resultsOrigen = [];
        }
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      if (isDestino) {
        _searchingDestino = true;
      } else {
        _searchingOrigen = true;
      }
    });

    try {
      List<AddressSuggestion> results;
      if (_searchMode == _SearchMode.reporte) {
        final reports = await _getAllReports();
        final lower = trimmed.toLowerCase();
        results = reports
            .where((r) => r.title.toLowerCase().contains(lower))
            .map(
              (r) => AddressSuggestion(
                displayName: '${r.title} · ${r.category}',
                latitude: r.latitude,
                longitude: r.longitude,
              ),
            )
            .toList();
      } else {
        results = await _geocodingService.searchAddress(trimmed);
      }
      if (!mounted) return;
      setState(() {
        if (isDestino) {
          _resultsDestino = results;
        } else {
          _resultsOrigen = results;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo buscar: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isDestino) {
            _searchingDestino = false;
          } else {
            _searchingOrigen = false;
          }
        });
      }
    }
  }

  void _addRecent(AddressSuggestion suggestion) {
    _recientes.removeWhere((r) => r.displayName == suggestion.displayName);
    _recientes.insert(0, suggestion);
    if (_recientes.length > 6) _recientes.removeLast();
  }

  void _selectDestino(AddressSuggestion suggestion) {
    setState(() {
      _destinoPoint = suggestion;
      _destinoController.text = suggestion.displayName;
      _resultsDestino = [];
      _route = null;
    });
    _addRecent(suggestion);
    FocusScope.of(context).unfocus();
    _tryComputeRoute();
  }

  void _selectOrigen(AddressSuggestion suggestion) {
    setState(() {
      _origenPoint = suggestion;
      _origenController.text = suggestion.displayName;
      _resultsOrigen = [];
      _route = null;
    });
    _addRecent(suggestion);
    FocusScope.of(context).unfocus();
    _tryComputeRoute();
  }

  void _toggleOrigenField() {
    setState(() {
      _showOrigenField = !_showOrigenField;
      if (!_showOrigenField) {
        _origenController.clear();
        _origenPoint = null;
        _resultsOrigen = [];
        _route = null;
        _tryComputeRoute();
      }
    });
  }

  /// Calcula la ruta. Si solo se dio el destino, usa la ubicación actual
  /// como punto de partida. Si además se especificó un origen propio,
  /// usa ambas direcciones tal cual se ingresaron (como antes).
  Future<void> _tryComputeRoute() async {
    if (_destinoPoint == null) return;

    setState(() {
      _loadingRoute = true;
      _errorMessage = null;
    });

    AddressSuggestion? origin = _origenPoint;
    if (origin == null) {
      final current = await _getCurrentLatLng();
      if (current == null) {
        if (mounted) {
          setState(() {
            _loadingRoute = false;
            _errorMessage = 'No se pudo obtener tu ubicación actual.';
          });
        }
        return;
      }
      origin = AddressSuggestion(
        displayName: _myLocationLabel,
        latitude: current.latitude,
        longitude: current.longitude,
      );
    }

    try {
      final result = await _routingService.getRoute(
        start: LatLng(origin.latitude, origin.longitude),
        end: LatLng(_destinoPoint!.latitude, _destinoPoint!.longitude),
        profile: _profile,
      );

      //Conectá el método con el cálculo de la ruta
      final reports = await _getAllReports();

      final affectedReports = _findReportsAlongRoute(result.points, reports);

      if (!mounted) return;
      setState(() {
        _route = result;
        _resolvedOrigin = origin;
        _routeReports = affectedReports;
      });
      _fitMapToPoints(origin, _destinoPoint!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo calcular la ruta: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  //Agrega sonido si en el recorrido del gps se acerca a un reporte
  Future<void> _playHazardAlert() async {
    try {
      await _alertPlayer.stop();
      await _alertPlayer.play(AssetSource('audio/alert.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('No se pudo reproducir la alerta: $e');
    }
  }

  // Agrega funcion para iniciar recorrido
  Future<void> _startRoute() async {
    if (_route == null || _isNavigating) return;

    try {
      // Comprueba que el GPS esté habilitado y tenga permisos.
      final position = await _locationService.getCurrentPosition();

      if (!mounted) return;

      //reiniciar las alertas al iniciar un recorrido nuevo
      _alertedReports.clear();

      setState(() {
        _isNavigating = true;
        _livePosition = LatLng(position.latitude, position.longitude);
        _errorMessage = null;
      });

      // Actualiza la ubicación durante el recorrido.
      _positionSubscription = _locationService.watchPosition().listen((
        position,
      ) {
        if (!mounted) return;

        final currentPosition = LatLng(position.latitude, position.longitude);

        setState(() {
          _livePosition = currentPosition;
        });

        _mapController.move(currentPosition, 16);

        const double alertDistanceMeters = 100;
        const distanceCalculator = Distance();

        for (final report in _routeReports) {
          final reportPosition = LatLng(report.latitude, report.longitude);

          final meters = distanceCalculator.as(
            LengthUnit.Meter,
            currentPosition,
            reportPosition,
          );

          final reportKey =
              '${report.latitude}_${report.longitude}_${report.title}';

          if (meters <= alertDistanceMeters &&
              !_alertedReports.contains(reportKey)) {
            _alertedReports.add(reportKey);

            _playHazardAlert();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '¡Atención! ${report.title} a menos de 100 metros.',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'No se pudo iniciar el recorrido: $e';
      });
    }
  }

  Future<void> _stopRoute() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!mounted) return;

    setState(() {
      _isNavigating = false;
    });
  }

  void _onProfileChanged(String profile) {
    if (_profile == profile) return;
    setState(() => _profile = profile);
    if (_destinoPoint != null) {
      _tryComputeRoute();
    }
  }

  void _onSearchModeChanged(_SearchMode mode) {
    if (_searchMode == mode) return;
    setState(() {
      _searchMode = mode;
      _resultsDestino = [];
      _resultsOrigen = [];
    });
  }

  String get _profileLabel {
    switch (_profile) {
      case 'cycling':
        return 'en bici';
      case 'walking':
        return 'caminando';
      case 'driving':
      default:
        return 'en auto';
    }
  }

  void _fitMapToPoints(AddressSuggestion a, AddressSuggestion b) {
    final bounds = LatLngBounds(
      LatLng(a.latitude, a.longitude),
      LatLng(b.latitude, b.longitude),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  String _formatKm(double km) {
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String _formatDuration(double minutes) {
    if (minutes < 60) {
      return '${minutes.round()} min';
    }
    final hours = minutes ~/ 60;
    final remainingMin = (minutes % 60).round();
    return '${hours}h ${remainingMin}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isNavigating
            ? _buildNavigationView()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      children: [
                        _buildDestinoField(),
                        const SizedBox(height: 6),
                        _buildOrigenToggle(),
                        if (_showOrigenField) ...[
                          const SizedBox(height: 8),
                          _buildOrigenField(),
                        ],
                        const SizedBox(height: 10),
                        _buildModeChips(),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'driving',
                              label: Text('Auto'),
                              icon: Icon(Icons.directions_car),
                            ),
                            ButtonSegment(
                              value: 'cycling',
                              label: Text('Bici'),
                              icon: Icon(Icons.directions_bike),
                            ),
                            ButtonSegment(
                              value: 'walking',
                              label: Text('Caminando'),
                              icon: Icon(Icons.directions_walk),
                            ),
                          ],
                          selected: {_profile},
                          onSelectionChanged: (selection) =>
                              _onProfileChanged(selection.first),
                        ),
                        if (_loadingRoute) ...[
                          const SizedBox(height: 16),
                          const CircularProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text(
                            'Calculando ruta...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                        if (!_loadingRoute && _route != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Desde ${_resolvedOrigin?.displayName ?? _myLocationLabel}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Distancia recorriendo calles',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatKm(_route!.distanceKm),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '≈ ${_formatDuration(_route!.durationMinutes)} $_profileLabel',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _startRoute,
                              icon: const Icon(Icons.navigation),
                              label: const Text('Iniciar recorrido'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  Expanded(child: _buildMap()),
                ],
              ),
      ),
    );
  }

  Widget _buildNavigationView() {
    return Stack(
      children: [
        // El mapa ocupa toda la pantalla.
        Positioned.fill(child: _buildMap()),

        // Información del recorrido en la parte superior.
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            elevation: 5,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.navigation, color: Colors.blue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Recorrido en curso',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Destino: ${_destinoPoint?.displayName ?? "No definido"}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_route != null)
                          Text(
                            '${_formatKm(_route!.distanceKm)} · '
                            '≈ ${_formatDuration(_route!.durationMinutes)}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Aviso de error, si el GPS falla.
        if (_errorMessage != null)
          Positioned(
            top: 115,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ),
          ),

        // Botón para terminar la navegación.
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopRoute,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Finalizar recorrido'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDestinoField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(28),
          color: Theme.of(context).colorScheme.surface,
          child: TextField(
            controller: _destinoController,
            onChanged: _onChangedDestino,
            decoration: InputDecoration(
              hintText: _searchMode == _SearchMode.calle
                  ? '¿A dónde vamos?'
                  : 'Buscar un reporte...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: _searchingDestino
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_destinoController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _destinoController.clear();
                              setState(() {
                                _destinoPoint = null;
                                _resultsDestino = [];
                                _route = null;
                              });
                            },
                          )
                        : null),
            ),
          ),
        ),
        if (_resultsDestino.isNotEmpty)
          _buildResultsList(_resultsDestino, _selectDestino)
        else if (_destinoController.text.trim().isEmpty &&
            _recientes.isNotEmpty)
          _buildRecientes(),
      ],
    );
  }

  Widget _buildOrigenToggle() {
    return Row(
      children: [
        Icon(Icons.my_location, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _showOrigenField
                ? 'Elegí tu punto de partida'
                : 'Desde: $_myLocationLabel',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _toggleOrigenField,
          child: Text(_showOrigenField ? 'Usar mi ubicación' : 'Cambiar'),
        ),
      ],
    );
  }

  Widget _buildOrigenField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _origenController,
          onChanged: _onChangedOrigen,
          decoration: InputDecoration(
            labelText: 'Punto de partida',
            hintText: 'Buscá una calle o dirección...',
            border: const OutlineInputBorder(),
            suffixIcon: _searchingOrigen
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_origenController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _origenController.clear();
                            setState(() {
                              _origenPoint = null;
                              _resultsOrigen = [];
                              _route = null;
                            });
                            _tryComputeRoute();
                          },
                        )
                      : null),
          ),
        ),
        if (_resultsOrigen.isNotEmpty)
          _buildResultsList(_resultsOrigen, _selectOrigen),
      ],
    );
  }

  Widget _buildResultsList(
    List<AddressSuggestion> results,
    ValueChanged<AddressSuggestion> onSelect,
  ) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final suggestion = results[index];
          return ListTile(
            dense: true,
            leading: Icon(
              _searchMode == _SearchMode.reporte
                  ? Icons.location_on_outlined
                  : Icons.place_outlined,
            ),
            title: Text(
              suggestion.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelect(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildRecientes() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Recientes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ..._recientes.map(
            (r) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: Text(
                r.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectDestino(r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips() {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Calle'),
          selected: _searchMode == _SearchMode.calle,
          onSelected: (_) => _onSearchModeChanged(_SearchMode.calle),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Reporte'),
          selected: _searchMode == _SearchMode.reporte,
          onSelected: (_) => _onSearchModeChanged(_SearchMode.reporte),
        ),
      ],
    );
  }

  Widget _buildMap() {
    // Al entrar a "Rutas" esperamos la ubicación real del usuario.
    // No usamos Buenos Aires como ubicación de respaldo.
    if (_loadingInitialLocation && _cachedCurrentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    //Corregir mapa cuando no hay ubicacion
    if (_cachedCurrentPosition == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se pudo obtener tu ubicación. '
            'Activá el GPS y revisá los permisos.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final origin = _resolvedOrigin ?? _origenPoint;
    final markers = <Marker>[
      if (origin != null)
        Marker(
          point: LatLng(origin.latitude, origin.longitude),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.green, size: 36),
        ),
      if (_destinoPoint != null)
        Marker(
          point: LatLng(_destinoPoint!.latitude, _destinoPoint!.longitude),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
        ),

      // muestra la ubicación actual en el mapa
      if (_isNavigating && _livePosition != null)
        Marker(
          point: _livePosition!,
          width: 48,
          height: 48,
          child: const Icon(Icons.navigation, color: Colors.blue, size: 38),
        ),

      // aparece un marcador naranja por cada reporte que este a menos de 80m en el recorrido
      ..._routeReports.map(
        (report) => Marker(
          point: LatLng(report.latitude, report.longitude),
          width: 45,
          height: 45,
          child: const Icon(
            Icons.warning_rounded,
            color: Colors.deepOrange,
            size: 34,
          ),
        ),
      ),
    ];

    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mapType = context.watch<MapLayerProvider>().mapType;

    //

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _cachedCurrentPosition!,
        initialZoom: 15,
      ),
      children: [
        buildMapTileLayer(mapType: mapType, isDark: isDark),
        if (_route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _route!.points,
                strokeWidth: 4,
                color: Colors.blue,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  @override
  void dispose() {
    _debounceDestino?.cancel();
    _debounceOrigen?.cancel();
    _positionSubscription?.cancel();
    _destinoController.dispose();
    _origenController.dispose();
    _alertPlayer.dispose();
    super.dispose();
  }
}
