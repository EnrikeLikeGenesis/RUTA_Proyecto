import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maneja el modo claro/oscuro de toda la app (interfaz + capa del mapa).
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  String _languageCode = 'es';
  bool _communityNotifications = false;
  bool _trafficNotifications = false;
  bool _promotionsNotifications = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String get languageCode => _languageCode;
  bool get isEnglish => _languageCode == 'en';
  bool get communityNotifications => _communityNotifications;
  bool get trafficNotifications => _trafficNotifications;
  bool get promotionsNotifications => _promotionsNotifications;

  Future<void> loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    _themeMode = preferences.getBool('dark_mode') == true
        ? ThemeMode.dark
        : ThemeMode.light;
    _languageCode = preferences.getString('language_code') ?? 'es';
    _communityNotifications =
        preferences.getBool('community_notifications') ?? false;
    _trafficNotifications =
        preferences.getBool('traffic_notifications') ?? false;
    _promotionsNotifications =
        preferences.getBool('promotions_notifications') ?? false;
  }

  Future<void> toggleDarkMode(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('dark_mode', enabled);
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setLanguageCode(String languageCode) async {
    if (languageCode != 'es' && languageCode != 'en') {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('language_code', languageCode);
    _languageCode = languageCode;
    notifyListeners();
  }

  Future<void> setCommunityNotifications(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('community_notifications', enabled);
    _communityNotifications = enabled;
    notifyListeners();
  }

  Future<void> setTrafficNotifications(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('traffic_notifications', enabled);
    _trafficNotifications = enabled;
    notifyListeners();
  }

  Future<void> setPromotionsNotifications(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('promotions_notifications', enabled);
    _promotionsNotifications = enabled;
    notifyListeners();
  }
}
