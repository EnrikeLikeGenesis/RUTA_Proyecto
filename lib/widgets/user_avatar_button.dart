import 'package:flutter/material.dart';
import '../screens/settings/settings_screen.dart';

/// Círculo de avatar que se ve en la barra superior del mapa y en la
/// búsqueda. Al tocarlo abre los Ajustes de la cuenta (o del invitado).
class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: colorScheme.primaryContainer,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
