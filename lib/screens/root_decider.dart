import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'auth/login_screen.dart';
import 'main_navigation_screen.dart';

/// Decide si mostrar el login, o la app (mapa/comunidad/rutas), ya sea
/// como usuario logueado o como invitado.
class RootDecider extends StatelessWidget {
  const RootDecider({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoggedIn) {
      return MainNavigationScreen(userId: authProvider.user!.id, isGuest: false);
    }
    if (authProvider.isGuest) {
      return const MainNavigationScreen(userId: null, isGuest: true);
    }
    return const LoginScreen();
  }
}
