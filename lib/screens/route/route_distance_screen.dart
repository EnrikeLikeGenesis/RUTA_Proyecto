import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../config/report_categories.dart';
import '../../l10n/app_text.dart';
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
  static const _routeReportRadiusMeters = 80.0;

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
  bool _isRecommendedRoute = false;
  List<ReportPoint> _reportsOnRoute = [];
  String? _reportsOnRouteError;
  int _routeRequestId = 0;
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

  String _routeReportSummary(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    if (_isRecommendedRoute && _reportsOnRoute.isNotEmpty) {
      return isEnglish
          ? '${_reportsOnRoute.length} unavoidable '
                '${_reportsOnRoute.length == 1 ? 'report' : 'reports'} on the recommended route'
          : '${_reportsOnRoute.length} '
                '${_reportsOnRoute.length == 1 ? 'reporte que no se pudo evitar' : 'reportes que no se pudieron evitar'} '
                'en la ruta recomendada';
    }
    if (_reportsOnRoute.isEmpty) {
      return appText(
        context,
        'Sin reportes en el recorrido',
        'No reports along the route',
      );
    }
    return _reportsOnRoute.length == 1
        ? appText(
            context,
            '1 reporte en el recorrido',
            '1 report along the route',
          )
        : (isEnglish
              ? '${_reportsOnRoute.length} reports along the route'
              : '${_reportsOnRoute.length} reportes en el recorrido');
  }

  String _myLocationLabel(BuildContext context) =>
      appText(context, 'Mi ubicación actual', 'My current location');

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
          displayName: appText(
            context,
            'Punto marcado en el mapa',
            'Point marked on the map',
          ),
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
      final position = await _locationService.getCurrentPosition(
        accuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
        isEnglish: Localizations.localeOf(context).languageCode == 'en',
      );
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
      setState(
        () =>
            _errorMessage = Localizations.localeOf(context).languageCode == 'en'
            ? 'Search failed: ${appErrorText(context, e)}'
            : 'No se pudo buscar: $e',
      );
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
      _routeReports = [];
      _isRecommendedRoute = false;
    });

    AddressSuggestion? origin = _origenPoint;
    if (origin == null) {
      final current = await _getCurrentLatLng();
      if (!mounted || requestId != _routeRequestId) return;
      if (current == null) {
        if (mounted) {
          setState(() {
            _loadingRoute = false;
            _errorMessage = appText(
              context,
              'No se pudo obtener tu ubicación actual.',
              'Could not get your current location.',
            );
          });
        }
        return;
      }
      origin = AddressSuggestion(
        displayName: _myLocationLabel(context),
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
          _routeReports = _findReportsAlongRoute(result.points, reports);
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
      setState(
        () =>
            _errorMessage = Localizations.localeOf(context).languageCode == 'en'
            ? 'Could not calculate route: ${appErrorText(context, e)}'
            : 'No se pudo calcular la ruta: $e',
      );
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
      final segmentLengthSquared = segmentX * segmentX + segmentY * segmentY;
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
    const previewLength = 160;
    final hasLongDescription = report.description.length > previewLength;
    var showFullReport = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  report.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(
                        reportCategoryText(
                          context,
                          reportCategoryFor(report.category)?.label ??
                              report.category,
                        ),
                      ),
                    ),
                    Text(
                      report.username ?? appText(context, 'Usuario', 'User'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (report.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    showFullReport || !hasLongDescription
                        ? report.description
                        : '${report.description.substring(0, previewLength).trimRight()}…',
                    maxLines: showFullReport ? null : 4,
                    overflow: showFullReport
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                ],
                if (showFullReport && report.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      report.imageUrl!,
                      width: double.infinity,
                      height: 260,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 260,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        height: 180,
                        alignment: Alignment.center,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Text(
                          appText(
                            context,
                            'No se pudo cargar la imagen',
                            'Could not load image',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (showFullReport) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${Localizations.localeOf(context).languageCode == 'en' ? 'Created' : 'Creado'}: ${report.createdAt.toLocal()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setSheetState(() => showFullReport = !showFullReport),
                    child: Text(
                      showFullReport
                          ? appText(context, 'Ver menos', 'See less')
                          : appText(context, 'Ver más', 'See more'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  //Agrega sonido si en el recorrido del gps se acerca a un reporte
  Future<void> _playHazardAlert() async {
    try {
      await _alertPlayer.stop();
      await _alertPlayer.play(AssetSource('audio/Alert.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('No se pudo reproducir la alerta: $e');
    }
  }

  Future<void> _startRoute({bool useRecommendedRoute = false}) async {
    if (_route == null || _isNavigating) return;

    if (useRecommendedRoute) {
      await _startRecommendedRoute();
      return;
    }

    await _beginNavigation();
  }

  Future<void> _startRecommendedRoute() async {
    final origin = _resolvedOrigin ?? _origenPoint;
    final destination = _destinoPoint;
    if (origin == null || destination == null) {
      setState(() {
        _errorMessage = appText(
          context,
          'No se pudo determinar el origen o el destino de la ruta.',
          'Could not determine the route origin or destination.',
        );
      });
      return;
    }

    setState(() {
      _loadingRoute = true;
      _errorMessage = null;
    });

    try {
      final reports = _allReportsCache ?? await _getAllReports();
      if (!mounted) return;
      final start = LatLng(origin.latitude, origin.longitude);
      final end = LatLng(destination.latitude, destination.longitude);
      final avoidableReports = reports.where((report) {
        final reportPoint = LatLng(report.latitude, report.longitude);
        final nearCurrentRoute =
            _distanceFromPointToRoute(reportPoint, _route!.points) <= 1000;
        final nearEndpoint =
            const Distance().as(LengthUnit.Meter, start, reportPoint) <= 120 ||
            const Distance().as(LengthUnit.Meter, end, reportPoint) <= 120;
        return nearCurrentRoute && !nearEndpoint;
      }).toList();
      final reportsToAvoid = {
        for (final report in avoidableReports) report.id: report,
      };

      var recommendedRoute = _route!;
      for (var attempt = 0; attempt < 3; attempt++) {
        recommendedRoute = await _routingService.getRouteAvoidingPoints(
          start: start,
          end: end,
          avoidPoints: reportsToAvoid.values
              .map((report) => LatLng(report.latitude, report.longitude))
              .toList(),
          profile: _profile,
        );
        if (!mounted) return;

        final remainingReports = reports.where(
          (report) =>
              _distanceFromPointToRoute(
                LatLng(report.latitude, report.longitude),
                recommendedRoute.points,
              ) <=
              _routeReportRadiusMeters,
        );
        var addedAvoidancePoint = false;
        for (final report in remainingReports) {
          final nearEndpoint =
              const Distance().as(
                    LengthUnit.Meter,
                    start,
                    LatLng(report.latitude, report.longitude),
                  ) <=
                  120 ||
              const Distance().as(
                    LengthUnit.Meter,
                    end,
                    LatLng(report.latitude, report.longitude),
                  ) <=
                  120;
          if (!nearEndpoint && !reportsToAvoid.containsKey(report.id)) {
            reportsToAvoid[report.id] = report;
            addedAvoidancePoint = true;
          }
        }
        if (!addedAvoidancePoint || attempt == 2) break;
      }

      setState(() {
        _route = recommendedRoute;
        _isRecommendedRoute = true;
        _routeReports = _findReportsAlongRoute(
          recommendedRoute.points,
          reports,
        );
        _reportsOnRoute = reports
            .where(
              (report) =>
                  _distanceFromPointToRoute(
                    LatLng(report.latitude, report.longitude),
                    recommendedRoute.points,
                  ) <=
                  _routeReportRadiusMeters,
            )
            .toList();
      });
      _fitMapToPoints(origin, destination);
      await _beginNavigation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = Localizations.localeOf(context).languageCode == 'en'
            ? 'Could not calculate recommended route: ${appErrorText(context, e)}'
            : 'No se pudo calcular la ruta recomendada: $e';
      });
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _beginNavigation() async {
    if (_route == null || _isNavigating) return;

    try {
      // Comprueba que el GPS esté habilitado y tenga permisos.
      final position = await _locationService.getCurrentPosition(
        accuracy: LocationAccuracy.high,
        isEnglish: Localizations.localeOf(context).languageCode == 'en',
      );

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
                  Localizations.localeOf(context).languageCode == 'en'
                      ? 'Warning! ${report.title} within 100 meters.'
                      : '¡Atención! ${report.title} a menos de 100 metros.',
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
        _errorMessage = Localizations.localeOf(context).languageCode == 'en'
            ? 'Could not start navigation: ${appErrorText(context, e)}'
            : 'No se pudo iniciar el recorrido: $e';
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
                    segments: [
                      ButtonSegment(
                        value: 'driving',
                        label: Text(appText(context, 'Auto', 'Car')),
                        icon: Icon(Icons.directions_car),
                      ),
                      ButtonSegment(
                        value: 'cycling',
                        label: Text(appText(context, 'Bici', 'Bike')),
                        icon: Icon(Icons.directions_bike),
                      ),
                      ButtonSegment(
                        value: 'walking',
                        label: Text(appText(context, 'Caminando', 'Walking')),
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
                    Text(
                      appText(
                        context,
                        'Calculando ruta...',
                        'Calculating route...',
                      ),
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
                            appText(context, 'Distancia', 'Distance'),
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
                                ? _routeReportSummary(context)
                                : (Localizations.localeOf(context)
                                              .languageCode ==
                                          'en'
                                      ? 'Could not load reports: ${appErrorText(context, _reportsOnRouteError!)}'
                                      : 'No se pudieron cargar los reportes: $_reportsOnRouteError'),
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
                    const SizedBox(height: 8),
                    if (_reportsOnRoute.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _startRoute(),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: Text(
                                appText(
                                  context,
                                  'Usar esta ruta',
                                  'Use this route',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  _startRoute(useRecommendedRoute: true),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: Text(
                                appText(
                                  context,
                                  'Ruta recomendada',
                                  'Recommended route',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startRoute,
                          icon: const Icon(Icons.navigation),
                          label: Text(
                            appText(
                              context,
                              'Iniciar recorrido',
                              'Start navigation',
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
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
                        Text(
                          appText(
                            context,
                            'Recorrido en curso',
                            'Navigation in progress',
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${appText(context, 'Destino', 'Destination')}: ${_destinoPoint?.displayName ?? appText(context, 'No definido', 'Not set')}',
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
                label: Text(
                  appText(context, 'Finalizar recorrido', 'End navigation'),
                ),
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
                  ? appText(context, '¿A dónde vamos?', 'Where are you going?')
                  : appText(
                      context,
                      'Buscar un reporte...',
                      'Search reports...',
                    ),
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
                ? appText(
                    context,
                    'Elegí tu punto de partida',
                    'Choose a starting point',
                  )
                : '${appText(context, 'From', 'Desde')}: ${_myLocationLabel(context)}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _toggleOrigenField,
          child: Text(
            _showOrigenField
                ? appText(context, 'Usar mi ubicación', 'Use my location')
                : appText(context, 'Cambiar', 'Change'),
          ),
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
            labelText: appText(context, 'Punto de partida', 'Starting point'),
            hintText: appText(
              context,
              'Buscá una calle o dirección...',
              'Search for a street or address...',
            ),
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
              appText(context, 'Recientes', 'Recent'),
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
          label: Text(appText(context, 'Calle', 'Address')),
          selected: _searchMode == _SearchMode.calle,
          onSelected: (_) => _onSearchModeChanged(_SearchMode.calle),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(appText(context, 'Reporte', 'Report')),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            appText(
              context,
              'No se pudo obtener tu ubicación. Activá el GPS y revisá los permisos.',
              'Could not get your location. Turn on GPS and check permissions.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final origin = _resolvedOrigin ?? _origenPoint;
    final hazardReportIds = _routeReports.map((report) => report.id).toSet();
    final markers = <Marker>[
      if (_route != null)
        ...?_allReportsCache?.map(
          (report) => Marker(
            point: LatLng(report.latitude, report.longitude),
            width: 56,
            height: 56,
            child: _buildRouteReportMarker(
              report,
              isHazard: hazardReportIds.contains(report.id),
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

      // muestra la ubicación actual en el mapa
      if (_isNavigating && _livePosition != null)
        Marker(
          point: _livePosition!,
          width: 48,
          height: 48,
          child: const Icon(Icons.navigation, color: Colors.blue, size: 38),
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

  Widget _buildRouteReportMarker(ReportPoint report, {required bool isHazard}) {
    return Semantics(
      button: true,
      label: isHazard
          ? (Localizations.localeOf(context).languageCode == 'en'
                ? '${report.title}, hazard report near route'
                : '${report.title}, reporte de peligro cerca de la ruta')
          : report.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showRouteReport(report),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: _routeReportMarker(report.category),
            ),
            if (isHazard)
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
