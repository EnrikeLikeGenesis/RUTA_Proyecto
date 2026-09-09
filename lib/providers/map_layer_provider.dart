import 'package:flutter/material.dart';

/// Tipos de capa de mapa disponibles.
enum MapLayerType { standard, terrain, satellite }

/// Maneja qué capa de mapa está activa (Estándar, Relieve o Satélite).
/// Es compartido entre todas las pantallas que muestran un mapa, para que
/// la elección sea consistente en toda la app.
class MapLayerProvider extends ChangeNotifier {
  MapLayerType _mapType = MapLayerType.standard;

  MapLayerType get mapType => _mapType;

  void setMapType(MapLayerType type) {
    if (_mapType == type) return;
    _mapType = type;
    notifyListeners();
  }
}
