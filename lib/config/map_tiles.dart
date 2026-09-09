/// URLs de las capas de teselas (tiles) usadas en los mapas de la app.
class MapTiles {
  MapTiles._();

  /// Identifica a la app ante los proveedores de mapas.
  static const String userAgentPackageName = 'com.example.ruta';

  // --- Estándar ---------------------------------------------------------
  /// Capa clara (OpenStreetMap estándar).
  static const String light = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Capa oscura (CARTO Dark Matter), gratuita y sin API key.
  static const String dark =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  static const List<String> darkSubdomains = ['a', 'b', 'c', 'd'];

  // --- Relieve ------------------------------------------------------------
  /// Capa de relieve/topográfica (OpenTopoMap), gratuita y sin API key.
  /// No existe una versión oscura propia de este proveedor: en modo
  /// oscuro se oscurecen las mismas teselas con un velo semitransparente.
  static const String terrain = 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';

  static const List<String> terrainSubdomains = ['a', 'b', 'c'];

  // --- Satélite -----------------------------------------------------------
  /// Imágenes satelitales (Esri World Imagery), gratuita y sin API key.
  /// Es la misma imagen en modo claro y oscuro: solo cambia el color de
  /// la interfaz alrededor del mapa, no la capa en sí.
  static const String satellite =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
}
