import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  double _fontSize = 16.0;

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  double get fontScale => _fontSize / 16.0;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDark = await PreferencesService.isDarkMode();
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _fontSize = await PreferencesService.getFontSize();
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    await PreferencesService.setDarkMode(isDark);
    notifyListeners();
  }

  void updateFontSize(double size) {
    _fontSize = size;
    notifyListeners();
  }

  Future<void> commitFontSize(double size) async {
    _fontSize = size;
    await PreferencesService.setFontSize(size);
    notifyListeners();
  }
}
