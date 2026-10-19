import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';
import 'account_details_screen.dart';
import 'help_screen.dart';
import 'my_reports_screen.dart';
import 'preferences_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<ThemeProvider>();
    final profile = auth.profile;
    final isEnglish = settings.isEnglish;
    final username =
        profile?['username'] as String? ??
        (isEnglish ? 'RÜTA user' : 'Usuario de RÜTA');
    final avatarUrl = profile?['avatar_url'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(isEnglish ? 'Account' : 'Cuenta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundImage: avatarUrl == null
                        ? null
                        : NetworkImage(avatarUrl),
                    child: avatarUrl == null
                        ? const Icon(Icons.person, size: 42)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(username, style: Theme.of(context).textTheme.titleLarge),
                  if (auth.isGuest) ...[
                    const SizedBox(height: 4),
                    Text(isEnglish ? 'Guest' : 'Invitado'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AccountTile(
            icon: Icons.manage_accounts_outlined,
            title: isEnglish ? 'My account' : 'Mi cuenta',
            subtitle: isEnglish
                ? 'Personal details and profile photo'
                : 'Datos personales y foto de perfil',
            enabled: !auth.isGuest,
            onTap: () => _open(context, const AccountDetailsScreen()),
          ),
          _AccountTile(
            icon: Icons.assignment_outlined,
            title: isEnglish ? 'My reports' : 'Lista de reportes',
            subtitle: isEnglish
                ? 'Reports you have created'
                : 'Reportes que realizaste',
            enabled: !auth.isGuest,
            onTap: () => _open(context, const MyReportsScreen()),
          ),
          _AccountTile(
            icon: Icons.help_outline,
            title: isEnglish ? 'Help' : 'Ayuda',
            subtitle: isEnglish
                ? 'Contact, terms, privacy and FAQs'
                : 'Contacto, términos, privacidad y preguntas frecuentes',
            onTap: () => _open(context, const HelpScreen()),
          ),
          _AccountTile(
            icon: Icons.tune,
            title: isEnglish ? 'Settings' : 'Ajustes',
            subtitle: isEnglish
                ? 'Notifications, language and theme'
                : 'Notificaciones, idioma y tema',
            onTap: () => _open(context, const PreferencesScreen()),
          ),
          if (auth.isGuest)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      isEnglish
                          ? 'Sign in to manage your personal details, reports and support requests.'
                          : 'Iniciá sesión para administrar tus datos, reportes y consultas de ayuda.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.login),
                      label: Text(
                        isEnglish
                            ? 'Sign in / Register'
                            : 'Iniciar sesión / Registrarme',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              if (auth.isGuest) {
                auth.exitGuest();
              } else {
                await auth.signOut();
              }
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.logout),
            label: Text(
              auth.isGuest
                  ? (isEnglish ? 'Leave guest mode' : 'Salir del modo invitado')
                  : (isEnglish ? 'Sign out' : 'Cerrar sesión'),
            ),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
