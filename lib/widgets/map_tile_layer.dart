import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../config/map_tiles.dart';
import '../providers/map_layer_provider.dart';

/// Arma la capa de teselas correspondiente al tipo de mapa elegido
/// (Estándar, Relieve o Satélite), respetando el modo claro/oscuro donde
/// corresponda:
/// - Estándar y Relieve tienen variante clara y oscura.
/// - Satélite es la misma imagen siempre; solo cambia el color de la
///   interfaz alrededor del mapa (eso lo maneja el tema de la app).
Widget buildMapTileLayer({required MapLayerType mapType, required bool isDark}) {
  switch (mapType) {
    case MapLayerType.satellite:
      return TileLayer(
        urlTemplate: MapTiles.satellite,
        userAgentPackageName: MapTiles.userAgentPackageName,
      );

    case MapLayerType.terrain:
      final tile = TileLayer(
        urlTemplate: MapTiles.terrain,
        subdomains: MapTiles.terrainSubdomains,
        userAgentPackageName: MapTiles.userAgentPackageName,
      );
      if (!isDark) return tile;
      return Stack(
        children: [
          Positioned.fill(child: tile),
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Color(0xB2101010)),
            ),
          ),
        ],
      );

    case MapLayerType.standard:
      return TileLayer(
        urlTemplate: isDark ? MapTiles.dark : MapTiles.light,
        subdomains: isDark ? MapTiles.darkSubdomains : const [],
        userAgentPackageName: MapTiles.userAgentPackageName,
      );
  }
}
