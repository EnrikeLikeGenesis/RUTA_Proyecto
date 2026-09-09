import 'dart:convert';
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

  /// [profile] puede ser 'driving', 'cycling' o 'walking'.
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng end,
    String profile = 'driving',
  }) async {
    final orsProfile = _toOrsProfile(profile);

    final uri = Uri.parse('$_baseUrl/$orsProfile').replace(queryParameters: {
      'api_key': RoutingConfig.apiKey,
      'start': '${start.longitude},${start.latitude}',
      'end': '${end.longitude},${end.latitude}',
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      if (response.statusCode == 403 || response.statusCode == 401) {
        throw Exception(
            'API key de OpenRouteService inválida o faltante (revisá lib/config/routing_config.dart)');
      }
      throw Exception('Error al calcular la ruta (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
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
