/// Configuración relacionada a la detección de reportes cercanos al usuario.
class ProximityConfig {
  ProximityConfig._();

  /// Radio (en metros) alrededor de la ubicación del usuario que se
  /// dibuja en el mapa y que se usa para decidir si un reporte recién
  /// creado dispara una notificación local.
  static const double alertRadiusMeters = 400;
}
