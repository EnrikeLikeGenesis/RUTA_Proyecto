import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_text.dart';
import 'comunidad/comunidad_screen.dart';
import 'home/home_map_screen.dart';
import 'route/route_distance_screen.dart';

/// Pantalla principal con comunidad y mapa; el buscador de rutas se abre
/// como una capa sobre el mapa.
class MainNavigationScreen extends StatefulWidget {
  final String? userId;
  final bool isGuest;

  const MainNavigationScreen({
    super.key,
    required this.userId,
    this.isGuest = false,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const _mapaIndex = 1;
  int _index = _mapaIndex;
  bool _communityVisited = false;
  bool _showRouteOverlay = false;

  /// Punto y propósito seleccionados desde el mapa para calcular un recorrido.
  LatLng? _markedPoint;
  bool _markedPointAsDestination = true;
  int _markedPointVersion = 0;

  void _goToTab(int index) {
    setState(() {
      _index = index;
      if (index == 0) _communityVisited = true;
      if (index != _mapaIndex) {
        _showRouteOverlay = false;
        _markedPoint = null;
      }
    });
  }

  void _showRoutes({LatLng? point, bool asDestination = true}) {
    setState(() {
      _markedPoint = point;
      _markedPointAsDestination = asDestination;
      _markedPointVersion++;
      _showRouteOverlay = true;
      _index = _mapaIndex;
    });
  }

  void _onMapPointMarked(LatLng point, bool asDestination) {
    _showRoutes(point: point, asDestination: asDestination);
  }

  void _closeRouteOverlay() {
    setState(() {
      _showRouteOverlay = false;
      _markedPoint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _communityVisited
          ? ComunidadScreen(currentUserId: widget.userId)
          : const SizedBox.shrink(),
      HomeMapScreen(
        userId: widget.userId,
        isGuest: widget.isGuest,
        onSearchTap: _showRoutes,
        onMapPointMarked: _onMapPointMarked,
      ),
    ];

    return PopScope<Object?>(
      canPop: !_showRouteOverlay,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showRouteOverlay) _closeRouteOverlay();
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(index: _index, children: tabs),
            if (_showRouteOverlay)
              Positioned.fill(
                child: RouteDistanceScreen(
                  key: ValueKey('route-$_markedPointVersion'),
                  initialMarkedPoint: _markedPoint,
                  initialMarkedPointAsDestination: _markedPointAsDestination,
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goToTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.groups_outlined),
              selectedIcon: const Icon(Icons.groups),
              label: appText(context, 'Comunidad', 'Community'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: appText(context, 'Mapa', 'Map'),
            ),
          ],
        ),
      ),
    );
  }
}
