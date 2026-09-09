import 'package:flutter/material.dart';
import '../../widgets/user_avatar_button.dart';

/// Pestaña "Comunidad". Por ahora es un placeholder: se puede ampliar más
/// adelante para mostrar publicaciones, comentarios o actividad de otros
/// usuarios de RÜTA.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunidad'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserAvatarButton(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'La comunidad de RÜTA está en camino',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Pronto vas a poder ver la actividad de otros usuarios acá.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
