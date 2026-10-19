import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/notification_service.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ThemeProvider>();
    final isEnglish = settings.isEnglish;

    return Scaffold(
      appBar: AppBar(title: Text(isEnglish ? 'Settings' : 'Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(
                    isEnglish ? 'Notifications' : 'Notificaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(
                    isEnglish ? 'Community alerts' : 'Avisos de la comunidad',
                  ),
                  subtitle: Text(
                    isEnglish
                        ? 'Nearby community reports'
                        : 'Reportes cercanos de la comunidad',
                  ),
                  value: settings.communityNotifications,
                  onChanged: (enabled) =>
                      _setCommunityNotifications(context, settings, enabled),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.traffic_outlined),
                  title: Text(
                    isEnglish ? 'Traffic alerts' : 'Alertas de tráfico',
                  ),
                  subtitle: Text(
                    isEnglish
                        ? 'Saved for when a traffic alert source is connected'
                        : 'Guardada para cuando se conecte una fuente de alertas',
                  ),
                  value: settings.trafficNotifications,
                  onChanged: (enabled) => _savePreference(
                    context,
                    settings.setTrafficNotifications(enabled),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.campaign_outlined),
                  title: Text(
                    isEnglish
                        ? 'News and promotions'
                        : 'Promociones y novedades',
                  ),
                  subtitle: Text(
                    isEnglish
                        ? 'Saved for when notifications become available'
                        : 'Guardada; las notificaciones aún no están activas',
                  ),
                  value: settings.promotionsNotifications,
                  onChanged: (enabled) => _savePreference(
                    context,
                    settings.setPromotionsNotifications(enabled),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(
                    isEnglish ? 'Appearance' : 'Apariencia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: Text(isEnglish ? 'Dark theme' : 'Tema oscuro'),
                  value: settings.isDarkMode,
                  onChanged: (enabled) => _savePreference(
                    context,
                    settings.toggleDarkMode(enabled),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(isEnglish ? 'Language' : 'Idioma'),
                  trailing: DropdownButton<String>(
                    value: settings.languageCode,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'es', child: Text('Español')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _savePreference(
                          context,
                          settings.setLanguageCode(value),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _savePreference(
    BuildContext context,
    Future<void> operation,
  ) async {
    try {
      await operation;
      return true;
    } catch (error) {
      if (!context.mounted) return false;
      final isEnglish = context.read<ThemeProvider>().isEnglish;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Could not save setting: $error'
                : 'No se pudo guardar el ajuste: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _setCommunityNotifications(
    BuildContext context,
    ThemeProvider settings,
    bool enabled,
  ) async {
    if (!await _savePreference(
      context,
      settings.setCommunityNotifications(enabled),
    )) {
      return;
    }
    if (!enabled) return;

    try {
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted && context.mounted) {
        final isEnglish = settings.isEnglish;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEnglish
                  ? 'Allow notifications in your device settings to receive community alerts.'
                  : 'Permití las notificaciones en los ajustes del dispositivo para recibir avisos.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      final isEnglish = settings.isEnglish;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Could not request notification permission: $error'
                : 'No se pudo solicitar el permiso de notificaciones: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
