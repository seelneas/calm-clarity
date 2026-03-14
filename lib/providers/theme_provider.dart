import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

class ThemeProvider with ChangeNotifier {
  double _fontSize = 16.0;

  double get fontSize => _fontSize;
  double get fontScale => _fontSize / 16.0;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    _fontSize = await PreferencesService.getFontSize();
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
