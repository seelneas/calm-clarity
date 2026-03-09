import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'auth_service.dart';
import 'preferences_service.dart';

class NotificationService {
  static const int _dailyReminderNotificationId = 1001;
  static const String _dailyChannelId = 'daily_reminders';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _localReady = false;
  static bool _firebaseReady = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!kIsWeb) {
      tz.initializeTimeZones();
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );
      await _localNotifications.initialize(initSettings);
      _localReady = true;

      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyChannelId,
          'Daily Reminders',
          description: 'Daily journaling reminders',
          importance: Importance.high,
        ),
      );
    }

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
        await syncPushTokenWithBackend();
      });
      FirebaseMessaging.onMessage.listen((message) async {
        final title = message.notification?.title ?? 'Calm Clarity';
        final body = message.notification?.body ??
            'You have a new notification.';
        await showInstantLocalNotification(title: title, body: body);
      });
    } catch (_) {
      _firebaseReady = false;
    }

    final notificationsEnabled =
        await PreferencesService.isNotificationsEnabled();
    final reminderEnabled = await PreferencesService.isDailyReminderEnabled();
    final hour = await PreferencesService.getDailyReminderHour();
    final minute = await PreferencesService.getDailyReminderMinute();

    if (notificationsEnabled && reminderEnabled) {
      await scheduleDailyReminder(hour: hour, minute: minute, syncBackend: false);
    }

    if (notificationsEnabled) {
      await syncPushTokenWithBackend();
      await syncPreferencesToBackend();
    }

    _initialized = true;
  }

  static Future<bool> areNotificationsGranted() async {
    if (kIsWeb) {
      return true;
    }
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  static Future<bool> requestNotificationPermissions() async {
    if (kIsWeb) {
      return true;
    }

    final permission = await Permission.notification.request();
    if (!permission.isGranted) {
      return false;
    }

    if (_firebaseReady) {
      final firebaseSettings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (firebaseSettings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
    }

    return true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    await PreferencesService.setNotificationsEnabled(enabled);
    if (!enabled) {
      await cancelDailyReminder(syncBackend: false);
      await syncPreferencesToBackend(
        notificationsEnabled: false,
      );
      return;
    }

    final reminderEnabled = await PreferencesService.isDailyReminderEnabled();
    final hour = await PreferencesService.getDailyReminderHour();
    final minute = await PreferencesService.getDailyReminderMinute();
    if (reminderEnabled) {
      await scheduleDailyReminder(
        hour: hour,
        minute: minute,
        syncBackend: false,
      );
    }

    await syncPushTokenWithBackend();
    await syncPreferencesToBackend(
      notificationsEnabled: true,
    );
  }

  static Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    bool syncBackend = true,
  }) async {
    await PreferencesService.setDailyReminderEnabled(true);
    await PreferencesService.setDailyReminderHour(hour);
    await PreferencesService.setDailyReminderMinute(minute);

    if (!_localReady || kIsWeb) {
      if (syncBackend) {
        await syncPreferencesToBackend();
      }
      return;
    }

    await _localNotifications.zonedSchedule(
      _dailyReminderNotificationId,
      'Time to check in',
      'Take 2 minutes to reflect and record your day.',
      _nextTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          'Daily Reminders',
          channelDescription: 'Daily journaling reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    if (syncBackend) {
      await syncPreferencesToBackend();
    }
  }

  static Future<void> cancelDailyReminder({bool syncBackend = true}) async {
    await PreferencesService.setDailyReminderEnabled(false);

    if (_localReady && !kIsWeb) {
      await _localNotifications.cancel(_dailyReminderNotificationId);
    }

    if (syncBackend) {
      await syncPreferencesToBackend();
    }
  }

  static Future<void> showInstantLocalNotification({
    required String title,
    required String body,
  }) async {
    if (!_localReady || kIsWeb) {
      return;
    }

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          'Daily Reminders',
          channelDescription: 'Daily journaling reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<Map<String, dynamic>> syncPushTokenWithBackend() async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    if (!_firebaseReady) {
      return {'success': false, 'message': 'Firebase not configured'};
    }

    final pushToken = await FirebaseMessaging.instance.getToken();
    if (pushToken == null || pushToken.trim().isEmpty) {
      return {'success': false, 'message': 'Push token unavailable'};
    }

    final deviceId = await PreferencesService.getOrCreateNotificationDeviceId();
    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/notifications/devices/register'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'device_id': deviceId,
        'platform': _platformName(),
        'push_token': pushToken,
        'push_enabled': true,
      }),
    );

    if (response.statusCode == 200) {
      return {'success': true};
    }

    final data = _decodeBody(response.body);
    return {
      'success': false,
      'message': data['detail'] ?? 'Failed to register device token',
    };
  }

  static Future<Map<String, dynamic>> syncPreferencesToBackend({
    bool? notificationsEnabled,
    bool? pushEnabled,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
  }) async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    final bool localNotificationsEnabled =
        notificationsEnabled ?? await PreferencesService.isNotificationsEnabled();
    final bool localReminderEnabled =
        dailyReminderEnabled ?? await PreferencesService.isDailyReminderEnabled();
    final int localHour =
        dailyReminderHour ?? await PreferencesService.getDailyReminderHour();
    final int localMinute =
        dailyReminderMinute ?? await PreferencesService.getDailyReminderMinute();

    final response = await http.put(
      Uri.parse('${AuthService.baseUrl}/notifications/preferences'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'notifications_enabled': localNotificationsEnabled,
        'push_enabled': pushEnabled ?? _firebaseReady,
        'daily_reminder_enabled': localReminderEnabled,
        'daily_reminder_hour': localHour,
        'daily_reminder_minute': localMinute,
        'timezone': DateTime.now().timeZoneName,
      }),
    );

    if (response.statusCode == 200) {
      return {'success': true};
    }

    final data = _decodeBody(response.body);
    return {
      'success': false,
      'message': data['detail'] ?? 'Failed to sync preferences',
    };
  }

  static Future<Map<String, dynamic>> fetchPreferencesFromBackend() async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/notifications/preferences'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    final data = _decodeBody(response.body);
    if (response.statusCode != 200) {
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to fetch preferences',
      };
    }

    return {
      'success': true,
      'notifications_enabled': data['notifications_enabled'] == true,
      'push_enabled': data['push_enabled'] == true,
      'daily_reminder_enabled': data['daily_reminder_enabled'] == true,
      'daily_reminder_hour': data['daily_reminder_hour'] ?? 20,
      'daily_reminder_minute': data['daily_reminder_minute'] ?? 0,
      'timezone': data['timezone'] ?? 'UTC',
    };
  }

  static Future<Map<String, dynamic>> triggerBackendNotification({
    required String eventType,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/notifications/trigger'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'event_type': eventType,
        'title': title,
        'body': body,
        'data': data,
      }),
    );

    final responseBody = _decodeBody(response.body);
    if (response.statusCode != 200) {
      return {
        'success': false,
        'message': responseBody['detail'] ?? 'Failed to trigger notification',
      };
    }

    return {
      'success': true,
      'event_type': responseBody['event_type'],
      'attempted': responseBody['attempted'] ?? 0,
      'sent': responseBody['sent'] ?? 0,
      'failed': responseBody['failed'] ?? 0,
    };
  }

  static Future<Map<String, dynamic>> fetchHealthFromBackend() async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/notifications/health'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    final data = _decodeBody(response.body);
    if (response.statusCode != 200) {
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to fetch notification health',
      };
    }

    return {'success': true, ...data};
  }

  static Future<Map<String, dynamic>> fetchAdminReadiness() async {
    final authToken = await PreferencesService.getAuthToken();
    if (authToken == null || authToken.trim().isEmpty) {
      return {'success': false, 'message': 'Sign in required'};
    }

    final adminApiKey = const String.fromEnvironment(
      'ADMIN_API_KEY',
      defaultValue: '',
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };
    if (adminApiKey.trim().isNotEmpty) {
      headers['X-Admin-Key'] = adminApiKey.trim();
    }

    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/admin/notifications/readiness'),
      headers: headers,
    );

    final data = _decodeBody(response.body);
    if (response.statusCode != 200) {
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to fetch admin readiness',
      };
    }

    return {'success': true, ...data};
  }

  static Future<Map<String, dynamic>> localDiagnosticsSnapshot() async {
    final notificationsEnabled =
        await PreferencesService.isNotificationsEnabled();
    final reminderEnabled =
        await PreferencesService.isDailyReminderEnabled();
    final reminderHour = await PreferencesService.getDailyReminderHour();
    final reminderMinute = await PreferencesService.getDailyReminderMinute();
    final granted = await areNotificationsGranted();

    String pushTokenState = 'unavailable';
    if (_firebaseReady) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        pushTokenState = (token != null && token.trim().isNotEmpty)
            ? 'available'
            : 'missing';
      } catch (_) {
        pushTokenState = 'error';
      }
    }

    return {
      'notifications_enabled': notificationsEnabled,
      'daily_reminder_enabled': reminderEnabled,
      'daily_reminder_hour': reminderHour,
      'daily_reminder_minute': reminderMinute,
      'permission_granted': granted,
      'firebase_ready': _firebaseReady,
      'local_ready': _localReady,
      'platform': _platformName(),
      'push_token_state': pushTokenState,
    };
  }

  static Future<void> notifyEntrySaved() async {
    final notificationsEnabled = await PreferencesService.isNotificationsEnabled();
    if (!notificationsEnabled) {
      return;
    }

    await showInstantLocalNotification(
      title: 'Entry saved',
      body: 'Great work showing up today. Keep your streak going.',
    );

    await triggerBackendNotification(
      eventType: 'entry_saved',
      title: 'Entry saved',
      body: 'Great work showing up today. Keep your streak going.',
      data: {'source': 'client_voice_entry'},
    );
  }

  static tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static Map<String, dynamic> _decodeBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
