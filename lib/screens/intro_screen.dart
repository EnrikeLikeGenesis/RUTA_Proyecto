import 'package:flutter/material.dart';

import 'auth/login_screen.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  static const Color azul = Color(0xFF164A9A);
  static const Color celeste = Color(0xFF58B5F5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mascota Rüta
                    Container(
                      width: double.infinity,
                      height: 330,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFDDF2FF), Colors.white],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(120),
                          bottomRight: Radius.circular(120),
                        ),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/mascota_ruta.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.image_not_supported_outlined,
                              size: 70,
                              color: celeste,
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      '¡Bienvenido a Rüta!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: azul,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Conocé el estado de las calles y elegí '
                      'recorridos más seguros.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7187A5),
                        fontSize: 18,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Único botón de la pantalla
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: celeste,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Comenzar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
