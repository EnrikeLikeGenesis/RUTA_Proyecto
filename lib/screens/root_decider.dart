import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'intro_screen.dart';
import 'main_navigation_screen.dart';

class RootDecider extends StatelessWidget {
  const RootDecider({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    //cuenta con sesion activa entra directamente al mapa.
    if (authProvider.isLoggedIn) {
      return MainNavigationScreen(
        userId: authProvider.user!.id,
        isGuest: false,
      );
    }

    // si eligio entrar como invitado
    if (authProvider.isGuest) {
      return const MainNavigationScreen(userId: null, isGuest: true);
    }

    // Sin sesion ni modo invitado, mostrar la introduccion.
    return const IntroScreen();
  }
}
