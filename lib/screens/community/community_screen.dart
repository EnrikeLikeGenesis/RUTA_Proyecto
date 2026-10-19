import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
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
        title: Text(appText(context, 'Comunidad', 'Community')),
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
              Text(
                appText(
                  context,
                  'La comunidad de RÜTA está en camino',
                  'The RÜTA community is coming soon',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                appText(
                  context,
                  'Pronto vas a poder ver la actividad de otros usuarios acá.',
                  "Soon you will be able to see other users' activity here.",
                ),
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
