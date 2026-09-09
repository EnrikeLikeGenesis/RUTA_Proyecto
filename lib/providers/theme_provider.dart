import 'package:flutter/material.dart';

/// Maneja el modo claro/oscuro de toda la app (interfaz + capa del mapa).
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleDarkMode(bool enabled) {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
