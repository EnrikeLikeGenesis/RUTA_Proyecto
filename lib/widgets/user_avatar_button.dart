import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/settings/settings_screen.dart';

/// Círculo de avatar que se ve en la barra superior del mapa y en la
/// búsqueda. Al tocarlo abre los Ajustes de la cuenta (o del invitado).
class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarUrl =
        context.watch<AuthProvider>().profile?['avatar_url'] as String?;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: colorScheme.primaryContainer,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? Icon(Icons.person, color: colorScheme.onPrimaryContainer)
                : null,
          ),
        ),
      ),
    );
  }
}
