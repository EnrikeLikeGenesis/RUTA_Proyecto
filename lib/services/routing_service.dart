import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/routing_config.dart';

/// Resultado de calcular una ruta entre dos puntos.
class RouteResult {
  final List<LatLng> points; // el trazado de la ruta, para dibujarla
  final double distanceKm;
  final double durationMinutes;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

/// Calcula rutas "recorriendo calles" (no en línea recta) usando
/// OpenRouteService, que a diferencia del demo público de OSRM sí soporta
/// varios medios de transporte (auto, bici, caminando) en su plan gratuito.
///
/// Hace falta una API key gratis (sin tarjeta): ver lib/config/routing_config.dart.
class RoutingService {
  static const _baseUrl = 'https://api.openrouteservice.org/v2/directions';
  static const _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const _requestTimeout = Duration(seconds: 20);

  /// [profile] puede ser 'driving', 'cycling' o 'walking'.
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng end,
    String profile = 'driving',
  }) async {
    final orsProfile = _toOrsProfile(profile);

    final uri = Uri.parse('$_baseUrl/$orsProfile').replace(
      queryParameters: {
        'api_key': RoutingConfig.apiKey,
        'start': '${start.longitude},${start.latitude}',
        'end': '${end.longitude},${end.latitude}',
      },
    );

    http.Response response;
    try {
      response = await _requestOpenRouteService(uri);
    } on TimeoutException {
      if (profile == 'driving') {
        return _getOsrmRoute(start: start, end: end);
      }
      throw Exception(
        'OpenRouteService tardó demasiado en calcular la ruta. '
        'Intentá nuevamente.',
      );
    } on http.ClientException {
      if (profile == 'driving') {
        return _getOsrmRoute(start: start, end: end);
      }
      throw Exception(
        'No se pudo conectar con OpenRouteService. Intentá nuevamente.',
      );
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 403 || response.statusCode == 401) {
        throw Exception(
          'API key de OpenRouteService inválida o faltante (revisá lib/config/routing_config.dart)',
        );
      }
      if (response.statusCode >= 500 && profile == 'driving') {
        return _getOsrmRoute(start: start, end: end);
      }
      if (response.statusCode >= 500) {
        throw Exception(
          'OpenRouteService no está disponible (${response.statusCode}). '
          'Intentá nuevamente en unos minutos.',
        );
      }
      throw Exception('Error al calcular la ruta (${response.statusCode})');
    }

    return _parseOpenRouteServiceResponse(response.body);
  }

  Future<RouteResult> getRouteAvoidingPoints({
    required LatLng start,
    required LatLng end,
    required List<LatLng> avoidPoints,
    String profile = 'driving',
    double avoidRadiusMeters = 80,
  }) async {
    if (avoidPoints.isEmpty) {
      return getRoute(start: start, end: end, profile: profile);
    }

    final uri = Uri.parse('$_baseUrl/${_toOrsProfile(profile)}/geojson');
    final avoidPolygons = avoidPoints
        .map((point) => [_makeAvoidanceRing(point, avoidRadiusMeters)])
        .toList();
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': RoutingConfig.apiKey,
            'Content-Type': 'application/json',
            'Accept': 'application/geo+json',
          },
          body: jsonEncode({
            'coordinates': [
              [start.longitude, start.latitude],
              [end.longitude, end.latitude],
            ],
            'options': {
              'avoid_polygons': {
                'type': 'MultiPolygon',
                'coordinates': avoidPolygons,
              },
            },
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(
          'API key de OpenRouteService inválida o sin permiso para calcular '
          'la ruta recomendada.',
        );
      }
      throw Exception(
        'No se pudo calcular una ruta evitando los reportes '
        '(${response.statusCode}).',
      );
    }

    return _parseOpenRouteServiceResponse(response.body);
  }

  List<List<double>> _makeAvoidanceRing(LatLng center, double radiusMeters) {
    const vertexCount = 16;
    final latitudeRadius = radiusMeters / 111320;
    final longitudeRadius =
        radiusMeters / (111320 * math.cos(center.latitude * math.pi / 180));
    final ring = List<List<double>>.generate(vertexCount + 1, (index) {
      final angle = 2 * math.pi * index / vertexCount;
      return [
        center.longitude + longitudeRadius * math.cos(angle),
        center.latitude + latitudeRadius * math.sin(angle),
      ];
    });
    return ring;
  }

  Future<http.Response> _requestOpenRouteService(Uri uri) async {
    http.Response response;
    try {
      response = await http.get(uri).timeout(_requestTimeout);
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    }

    if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      response = await http.get(uri).timeout(_requestTimeout);
    }
    return response;
  }

  RouteResult _parseOpenRouteServiceResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>?;

    if (features == null || features.isEmpty) {
      throw Exception('No se encontró una ruta entre esos dos puntos.');
    }

    final feature = features.first as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;

    final points = coords.map((c) {
      final pair = c as List<dynamic>;
      // ORS devuelve [longitud, latitud]
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();

    final properties = feature['properties'] as Map<String, dynamic>;
    final summary = properties['summary'] as Map<String, dynamic>;
    final distanceMeters = (summary['distance'] as num).toDouble();
    final durationSeconds = (summary['duration'] as num).toDouble();

    return RouteResult(
      points: points,
      distanceKm: distanceMeters / 1000,
      durationMinutes: durationSeconds / 60,
    );
  }

  Future<RouteResult> _getOsrmRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    final uri =
        Uri.parse(
          '$_osrmBaseUrl/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}',
        ).replace(
          queryParameters: const {
            'overview': 'full',
            'geometries': 'geojson',
            'steps': 'false',
          },
        );

    final response = await http.get(uri).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo calcular la ruta. OpenRouteService devolvió un error '
        'temporal y el servicio alternativo respondió '
        '${response.statusCode}. Intentá nuevamente.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (data['code'] != 'Ok' || routes == null || routes.isEmpty) {
      throw Exception('No se encontró una ruta en auto entre esos dos puntos.');
    }

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final points = coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();

    return RouteResult(
      points: points,
      distanceKm: (route['distance'] as num).toDouble() / 1000,
      durationMinutes: (route['duration'] as num).toDouble() / 60,
    );
  }

  String _toOrsProfile(String profile) {
    switch (profile) {
      case 'cycling':
        return 'cycling-regular';
      case 'walking':
        return 'foot-walking';
      case 'driving':
      default:
        return 'driving-car';
    }
  }
}
