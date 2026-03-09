import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';

class PreferencesService {
  static const String _keyShowOnboarding = 'show_onboarding';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyDarkMode = 'dark_mode';
  static const String _keyFontSize = 'font_size';
  static const String _keyProfilePhoto = 'profile_photo';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyAutoSyncEnabled = 'auto_sync_enabled';
  static const String _keyLastBackupDate = 'last_backup_date';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyGoogleCalendarConnected = 'google_calendar_connected';
  static const String _keyAppleHealthConnected = 'apple_health_connected';
  static const String _keyAiProcessingEnabled = 'ai_processing_enabled';
  static const String _keyNotificationReminderEnabled = 'notification_daily_reminder_enabled';
  static const String _keyNotificationReminderHour = 'notification_daily_reminder_hour';
  static const String _keyNotificationReminderMinute = 'notification_daily_reminder_minute';
  static const String _keyNotificationDeviceId = 'notification_device_id';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowOnboarding) ?? true;
  }

  static Future<void> setOnboardingShowed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowOnboarding, false);
  }

  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? 'Alex Rivers';
  }

  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
  }

  static Future<String> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail) ?? 'alex.rivers@calmclarity.com';
  }

  static Future<void> setUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email);
  }

  static Future<bool> isDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? true;
  }

  static Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
  }

  static Future<double> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyFontSize) ?? 16.0;
  }

  static Future<void> setFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, value);
  }

  static Future<String?> getProfilePhotoPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyProfilePhoto);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  static Future<void> setProfilePhotoPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.trim().isEmpty) {
      await prefs.remove(_keyProfilePhoto);
      return;
    }
    await prefs.setString(_keyProfilePhoto, path);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, value);
  }

  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsEnabled, value);
  }

  static Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSyncEnabled) ?? false;
  }

  static Future<void> setAutoSyncEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSyncEnabled, value);
  }

  static Future<String?> getLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastBackupDate);
  }

  static Future<void> setLastBackupDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastBackupDate, date);
  }

  static Future<String?> getAuthToken() async {
    try {
      return await _secureStorage.read(key: _keyAuthToken);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAuthToken);
    }
  }

  static Future<void> setAuthToken(String token) async {
    try {
      if (token.isEmpty) {
        await _secureStorage.delete(key: _keyAuthToken);
      } else {
        await _secureStorage.write(key: _keyAuthToken, value: token);
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAuthToken, token);
    }
  }

  static Future<bool> isAuthenticated() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  static Future<bool> isGoogleCalendarConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGoogleCalendarConnected) ?? false;
  }

  static Future<void> setGoogleCalendarConnected(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGoogleCalendarConnected, value);
  }

  static Future<bool> isAppleHealthConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAppleHealthConnected) ?? false;
  }

  static Future<void> setAppleHealthConnected(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAppleHealthConnected, value);
  }

  static Future<bool> isAiProcessingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAiProcessingEnabled) ?? true;
  }

  static Future<void> setAiProcessingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAiProcessingEnabled, value);
  }

  static Future<bool> isDailyReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationReminderEnabled) ?? false;
  }

  static Future<void> setDailyReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationReminderEnabled, value);
  }

  static Future<int> getDailyReminderHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNotificationReminderHour) ?? 20;
  }

  static Future<void> setDailyReminderHour(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNotificationReminderHour, value);
  }

  static Future<int> getDailyReminderMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNotificationReminderMinute) ?? 0;
  }

  static Future<void> setDailyReminderMinute(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNotificationReminderMinute, value);
  }

  static Future<String> getOrCreateNotificationDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyNotificationDeviceId);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_keyNotificationDeviceId, id);
    return id;
  }

  // Helper to reset for testing if needed
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowOnboarding, true);
  }
}
