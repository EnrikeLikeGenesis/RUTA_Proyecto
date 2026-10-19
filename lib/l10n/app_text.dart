import 'package:flutter/widgets.dart';

String appText(BuildContext context, String spanish, String english) {
  return Localizations.localeOf(context).languageCode == 'en'
      ? english
      : spanish;
}

String reportCategoryText(BuildContext context, String category) {
  if (Localizations.localeOf(context).languageCode != 'en') return category;
  return switch (category.toLowerCase()) {
    'baches' || 'potholes' => 'Potholes',
    'obras' || 'roadworks' => 'Roadworks',
    'transito' || 'tránsito' || 'traffic' => 'Traffic',
    'zonas_inseguras' || 'zonas inseguras' || 'unsafe areas' => 'Unsafe areas',
    'accidentes' || 'accidents' => 'Accidents',
    'inundaciones' || 'flooding' => 'Flooding',
    'peligro' || 'hazard' => 'Hazard',
    'evento' || 'event' => 'Event',
    'general' => 'General',
    _ => category,
  };
}

String appErrorText(BuildContext context, Object error) {
  final message = error.toString();
  if (Localizations.localeOf(context).languageCode != 'en') return message;

  if (message.contains('OpenRouteService tardó demasiado')) {
    return 'OpenRouteService timed out. Please try again.';
  }
  if (message.contains('No se pudo conectar con OpenRouteService')) {
    return 'Could not connect to OpenRouteService. Please try again.';
  }
  if (message.contains('API key de OpenRouteService')) {
    return 'OpenRouteService API key is invalid or missing.';
  }
  if (message.contains('No se pudo calcular una ruta evitando los reportes')) {
    return message.replaceFirst(
      'No se pudo calcular una ruta evitando los reportes',
      'Could not calculate a route avoiding reports',
    );
  }
  if (message.contains('No se pudo calcular una ruta evitando puntos')) {
    return message.replaceFirst(
      'No se pudo calcular una ruta evitando puntos',
      'Could not calculate a route avoiding points',
    );
  }
  if (message.contains('OpenRouteService no está disponible')) {
    return message
        .replaceFirst('OpenRouteService no está disponible', 'OpenRouteService is unavailable')
        .replaceAll('Intentá nuevamente en unos minutos.', 'Try again in a few minutes.');
  }
  if (message.contains('No se encontró una ruta')) {
    return message
        .replaceFirst('No se encontró una ruta entre esos dos puntos.', 'No route was found between those points.')
        .replaceFirst('No se encontró una ruta en auto entre esos dos puntos.', 'No driving route was found between those points.');
  }
  if (message.contains('Error al calcular la ruta')) {
    return message.replaceFirst('Error al calcular la ruta', 'Error calculating route');
  }
  if (message.contains('Error al buscar la dirección')) {
    return message.replaceFirst('Error al buscar la dirección', 'Error searching for address');
  }
  if (message.contains('No se pudo obtener tu ubicación')) {
    return 'Could not get your location. Check GPS and location permissions.';
  }
  if (message.contains('Permiso de ubicación denegado')) {
    return 'Location permission denied. Enable location access in device settings.';
  }
  return message;
}
