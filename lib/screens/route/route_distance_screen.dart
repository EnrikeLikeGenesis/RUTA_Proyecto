import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../config/report_categories.dart';
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
  /// Punto y uso seleccionados por el usuario desde el mapa.
  final LatLng? initialMarkedPoint;
  final bool initialMarkedPointAsDestination;

  const RouteDistanceScreen({
    super.key,
    this.initialMarkedPoint,
    this.initialMarkedPointAsDestination = true,
  });

  @override
  State<RouteDistanceScreen> createState() => _RouteDistanceScreenState();
}

class _RouteDistanceScreenState extends State<RouteDistanceScreen> {
  static const _myLocationLabel = 'Mi ubicación actual';
  static const _routeReportRadiusMeters = 50.0;

  final _geocodingService = GeocodingService();
  final _routingService = RoutingService();
  final _locationService = LocationService();
  final _reportService = ReportService();
  final _mapController = MapController();

  final _destinoController = TextEditingController();
  final _origenController = TextEditingController();

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
  List<ReportPoint> _reportsOnRoute = [];
  String? _reportsOnRouteError;
  int _routeRequestId = 0;
  bool _loadingRoute = false;
  String _profile = 'driving'; // 'driving' | 'cycling' | 'walking'

  String? _errorMessage;

  LatLng? _cachedCurrentPosition;
  bool _loadingInitialLocation = true;

  @override
  void initState() {
    super.initState();
    _initializeMapLocation();
    if (widget.initialMarkedPoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _useMarkedPoint(
          widget.initialMarkedPoint!,
          asDestination: widget.initialMarkedPointAsDestination,
        );
      });
    }
  }

  Future<void> _initializeMapLocation() async {
    await _getCurrentLatLng();
    if (!mounted) return;
    setState(() => _loadingInitialLocation = false);
  }

  /// Usa el punto del mapa como destino o como punto de partida.
  Future<void> _useMarkedPoint(
    LatLng point, {
    required bool asDestination,
  }) async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
      if (asDestination) {
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

    if (asDestination) {
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

    final requestId = ++_routeRequestId;
    setState(() {
      _loadingRoute = true;
      _errorMessage = null;
      _reportsOnRoute = [];
      _reportsOnRouteError = null;
    });

    AddressSuggestion? origin = _origenPoint;
    if (origin == null) {
      final current = await _getCurrentLatLng();
      if (!mounted || requestId != _routeRequestId) return;
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
      if (!mounted || requestId != _routeRequestId) return;
      setState(() {
        _route = result;
        _resolvedOrigin = origin;
      });
      _fitMapToPoints(origin, _destinoPoint!);

      try {
        final reports = await _getAllReports();
        if (!mounted || requestId != _routeRequestId) return;
        setState(() {
          _reportsOnRoute = reports
              .where(
                (report) =>
                    _distanceFromPointToRoute(
                      LatLng(report.latitude, report.longitude),
                      result.points,
                    ) <=
                    _routeReportRadiusMeters,
              )
              .toList();
        });
      } catch (e) {
        if (!mounted || requestId != _routeRequestId) return;
        setState(() => _reportsOnRouteError = e.toString());
      }
    } catch (e) {
      if (!mounted || requestId != _routeRequestId) return;
      setState(() => _errorMessage = 'No se pudo calcular la ruta: $e');
    } finally {
      if (mounted && requestId == _routeRequestId) {
        setState(() => _loadingRoute = false);
      }
    }
  }

  double _distanceFromPointToRoute(LatLng point, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return double.infinity;

    final latitudeScale = 110574.0;
    final longitudeScale = 111320.0 * math.cos(point.latitude * math.pi / 180);
    final routeSegments = routePoints.length == 1
        ? [(routePoints.first, routePoints.first)]
        : [
            for (var i = 0; i < routePoints.length - 1; i++)
              (routePoints[i], routePoints[i + 1]),
          ];
    var nearestDistance = double.infinity;

    for (final (start, end) in routeSegments) {
      final startX = (start.longitude - point.longitude) * longitudeScale;
      final startY = (start.latitude - point.latitude) * latitudeScale;
      final segmentX = (end.longitude - start.longitude) * longitudeScale;
      final segmentY = (end.latitude - start.latitude) * latitudeScale;
      final segmentLengthSquared =
          segmentX * segmentX + segmentY * segmentY;
      final projection = segmentLengthSquared == 0
          ? 0.0
          : (-startX * segmentX - startY * segmentY) / segmentLengthSquared;
      final fraction = projection.clamp(0.0, 1.0);
      final distanceX = startX + fraction * segmentX;
      final distanceY = startY + fraction * segmentY;
      nearestDistance = math.min(
        nearestDistance,
        math.sqrt(distanceX * distanceX + distanceY * distanceY),
      );
    }

    return nearestDistance;
  }

  void _showRouteReport(ReportPoint report) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(reportCategoryFor(report.category)?.label ?? report.category),
              if (report.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(report.description),
              ],
            ],
          ),
        ),
      ),
    );
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
        child: Column(
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
                            style: TextStyle(fontSize: 13, color: Colors.grey),
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
                          const SizedBox(height: 8),
                          Text(
                            _reportsOnRouteError == null
                                ? _reportsOnRoute.length == 1
                                    ? '1 reporte en el recorrido'
                                    : '${_reportsOnRoute.length} reportes en el recorrido'
                                : 'No se pudieron cargar los reportes: $_reportsOnRouteError',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: _reportsOnRouteError == null
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
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

    final origin = _resolvedOrigin ?? _origenPoint;
    final markers = <Marker>[
      if (_route != null)
        ..._reportsOnRoute.map(
          (report) => Marker(
            point: LatLng(report.latitude, report.longitude),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showRouteReport(report),
              child: _routeReportMarker(report.category),
            ),
          ),
        ),
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
    ];

    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mapType = context.watch<MapLayerProvider>().mapType;

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

  Widget _routeReportMarker(String category) {
    final reportCategory = reportCategoryFor(category);
    if (reportCategory == null) {
      return const Icon(Icons.location_on, color: Colors.orange, size: 36);
    }

    return Image.asset(
      reportCategory.markerAsset,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
    );
  }

  @override
  void dispose() {
    _debounceDestino?.cancel();
    _debounceOrigen?.cancel();
    _destinoController.dispose();
    _origenController.dispose();
    super.dispose();
  }
}
