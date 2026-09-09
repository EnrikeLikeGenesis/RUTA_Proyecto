import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'comunidad/comunidad_screen.dart';
import 'home/home_map_screen.dart';
import 'route/route_distance_screen.dart';

/// Pantalla principal luego de entrar (logueado o invitado): agrupa las
/// tres secciones de la app en una barra de navegación inferior.
class MainNavigationScreen extends StatefulWidget {
  final String? userId;
  final bool isGuest;

  const MainNavigationScreen({super.key, required this.userId, this.isGuest = false});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const _mapaIndex = 1;
  int _index = _mapaIndex;

  /// Punto que el usuario marcó tocando el mapa, pendiente de usarse en
  /// la pestaña "Rutas". Cada vez que cambia se fuerza la recreación de
  /// [RouteDistanceScreen] (vía [_markedPointVersion]) para que le
  /// vuelva a preguntar al usuario cómo quiere usarlo.
  LatLng? _markedPoint;
  int _markedPointVersion = 0;

  void _goToTab(int index) => setState(() => _index = index);

  void _onMapPointMarked(LatLng point) {
    setState(() {
      _markedPoint = point;
      _markedPointVersion++;
      _index = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ComunidadScreen(currentUserId: widget.userId),
      HomeMapScreen(
        userId: widget.userId,
        isGuest: widget.isGuest,
        onSearchTap: () => _goToTab(2),
        onMapPointMarked: _onMapPointMarked,
      ),
      RouteDistanceScreen(
        key: ValueKey('route-$_markedPointVersion'),
        initialMarkedPoint: _markedPoint,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goToTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Comunidad',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route),
            label: 'Rutas',
          ),
        ],
      ),
    );
  }
}
