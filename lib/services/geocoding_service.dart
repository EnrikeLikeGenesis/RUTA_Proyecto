import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resultado de una búsqueda de dirección/calle.
class AddressSuggestion {
  final String displayName;
  final double latitude;
  final double longitude;

  AddressSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

/// Busca direcciones/calles usando Nominatim, el geocoder gratuito de
/// OpenStreetMap (no pide API key ni tarjeta de crédito, igual que los
/// mapas de flutter_map).
///
/// Nota: Nominatim es un servicio público con límite de uso (~1 request
/// por segundo). Para una app en producción con mucho tráfico conviene
/// alojar tu propia instancia o usar un proveedor pago, pero para este
/// proyecto alcanza de sobra.
class GeocodingService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org/search';
  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';

  /// Busca la dirección más cercana a un punto del mapa (geocodificación
  /// inversa). Se usa para mostrarle al usuario un nombre legible cuando
  /// marca un punto tocando el mapa, en vez de mostrarle coordenadas.
  /// Si falla o no hay resultado, devuelve null.
  Future<AddressSuggestion?> reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
      'lat': '$latitude',
      'lon': '$longitude',
      'format': 'json',
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'RUTA_Proyecto Flutter App',
        },
      );
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final displayName = data['display_name'] as String?;
      if (displayName == null) return null;

      return AddressSuggestion(
        displayName: displayName,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<AddressSuggestion>> searchAddress(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': trimmed,
      'format': 'json',
      'limit': '5',
      'addressdetails': '0',
    });

    final response = await http.get(
      uri,
      headers: {
        // Nominatim exige identificar la app que hace las consultas.
        'User-Agent': 'RUTA_Proyecto Flutter App',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Error al buscar la dirección (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return AddressSuggestion(
        displayName: map['display_name'] as String,
        latitude: double.parse(map['lat'] as String),
        longitude: double.parse(map['lon'] as String),
      );
    }).toList();
  }
}
