import 'package:flutter/material.dart';
import 'root_decider.dart';

/// Se muestra apenas se abre la app con un mensaje de bienvenida y, tras
/// una breve animación, da paso a la pantalla correspondiente
/// (login, invitado o mapa) sin usar rutas de Navigator adicionales.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showWelcome = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _showWelcome ? _buildWelcome(context) : const RootDecider(),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('welcome'),
      backgroundColor: colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alt_route, size: 88, color: colorScheme.onPrimary),
            const SizedBox(height: 20),
            Text(
              'Bienvenido a RÜTA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
