import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'preferences_service.dart';

class AuthService {
  // Configure with:
  // flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  // flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<client-id>
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: '',
    ),
  );

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb && googleWebClientId.isNotEmpty
        ? googleWebClientId
        : null,
    scopes: ['email', 'profile'],
  );

  static final GoogleSignIn _googleCalendarSignIn = GoogleSignIn(
    clientId: kIsWeb && googleWebClientId.isNotEmpty
        ? googleWebClientId
        : null,
    scopes: [
      'email',
      'profile',
      'https://www.googleapis.com/auth/calendar.events',
      'https://www.googleapis.com/auth/calendar.readonly',
    ],
  );

  static Timer? _googleCalendarSyncTimer;
  static bool _googleCalendarSyncInFlight = false;
  static Duration _googleCalendarSyncInterval = const Duration(minutes: 5);

  static Future<Map<String, dynamic>> signup(String name, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(data);
        return {'success': true};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Signup failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(data);
        return {'success': true};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<void> _handleAuthSuccess(Map<String, dynamic> data) async {
    final token = data['access_token'];
    final user = data['user'];
    await PreferencesService.setAuthToken(token);
    await PreferencesService.setUserName(user['name'] ?? '');
    await PreferencesService.setUserEmail(user['email']);
  }

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      if (kIsWeb && googleWebClientId.isEmpty) {
        return {
          'success': false,
          'message':
              'Google Web Client ID missing. Run with --dart-define=GOOGLE_WEB_CLIENT_ID=<id> (or --dart-define=GOOGLE_CLIENT_ID=<id>).',
        };
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return {'success': false, 'message': 'Sign in cancelled'};

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) return {'success': false, 'message': 'Failed to get ID token'};

      final response = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': idToken,
          'provider': 'google',
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(data);
        return {'success': true};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Google login failed'};
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return {'success': false, 'message': 'Google Sign-In Error: ${e.toString().split('\n').first}'};
    }
  }

  static Future<Map<String, dynamic>> updateIntegrations(String email, bool google, bool apple) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_integrations?email=$email&google=${google ? 1 : 0}&apple=${apple ? 1 : 0}'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'user': data};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Update failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<String?> _ensureCalendarAccessToken({
    bool allowInteractive = true,
  }) async {
    GoogleSignInAccount? account = _googleCalendarSignIn.currentUser;
    account ??= await _googleCalendarSignIn.signInSilently();
    if (allowInteractive) {
      account ??= await _googleCalendarSignIn.signIn();
    }
    if (account == null) {
      return null;
    }

    final auth = await account.authentication;
    return auth.accessToken;
  }

  static Future<Map<String, dynamic>> connectGoogleCalendar() async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final googleAccessToken = await _ensureCalendarAccessToken();
      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        return {'success': false, 'message': 'Google Calendar authorization cancelled'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/integrations/google-calendar/connect'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
        body: jsonEncode({'access_token': googleAccessToken}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await PreferencesService.setGoogleCalendarConnected(true);
        await startGoogleCalendarAutoSyncIfEnabled();
        return {
          'success': true,
          'message': data['message'] ?? 'Google Calendar connected',
          'access_token': googleAccessToken,
        };
      }

      return {'success': false, 'message': data['detail'] ?? 'Google Calendar connection failed'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> disconnectGoogleCalendar() async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/integrations/google-calendar/disconnect'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await PreferencesService.setGoogleCalendarConnected(false);
        await stopGoogleCalendarAutoSyncLoop();
        await _googleCalendarSignIn.disconnect().catchError((_) async {
          await _googleCalendarSignIn.signOut();
          return null;
        });
        return {'success': true, 'message': data['message'] ?? 'Google Calendar disconnected'};
      }

      return {'success': false, 'message': data['detail'] ?? 'Disconnect failed'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> fetchGoogleCalendarEvents() async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final googleAccessToken = await _ensureCalendarAccessToken();
      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        return {'success': false, 'message': 'Google Calendar authorization required'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/integrations/google-calendar/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
        body: jsonEncode({'access_token': googleAccessToken}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'connected': data['connected'] == true,
          'events': List<Map<String, dynamic>>.from(data['events'] ?? const []),
        };
      }

      return {'success': false, 'message': data['detail'] ?? 'Failed to fetch events'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getGoogleCalendarSyncStatus() async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/integrations/google-calendar/sync/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, ...Map<String, dynamic>.from(data)};
      }
      return {'success': false, 'message': data['detail'] ?? 'Failed to fetch sync status'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateGoogleCalendarSyncSettings({
    required bool autoSyncEnabled,
    required int syncIntervalMinutes,
  }) async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final response = await http.put(
        Uri.parse('$baseUrl/integrations/google-calendar/sync/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
        body: jsonEncode({
          'auto_sync_enabled': autoSyncEnabled,
          'sync_interval_minutes': syncIntervalMinutes,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, ...Map<String, dynamic>.from(data)};
      }
      return {'success': false, 'message': data['detail'] ?? 'Failed to update sync settings'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> runGoogleCalendarSync({
    List<Map<String, dynamic>> localChanges = const [],
    bool allowInteractive = true,
  }) async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final googleAccessToken = await _ensureCalendarAccessToken(
        allowInteractive: allowInteractive,
      );
      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        return {'success': false, 'message': 'Google Calendar authorization required'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/integrations/google-calendar/sync/run'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
        body: jsonEncode({
          'access_token': googleAccessToken,
          'local_changes': localChanges,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, ...Map<String, dynamic>.from(data)};
      }
      return {'success': false, 'message': data['detail'] ?? 'Failed to run calendar sync'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<void> _runGoogleCalendarAutoSyncTick() async {
    if (_googleCalendarSyncInFlight) {
      return;
    }
    _googleCalendarSyncInFlight = true;
    try {
      final authenticated = await PreferencesService.isAuthenticated();
      final connected = await PreferencesService.isGoogleCalendarConnected();
      final autoSyncEnabled = await PreferencesService.isAutoSyncEnabled();
      if (!authenticated || !connected || !autoSyncEnabled) {
        await stopGoogleCalendarAutoSyncLoop();
        return;
      }

      final status = await getGoogleCalendarSyncStatus();
      if (status['success'] == true && status['auto_sync_enabled'] == false) {
        await stopGoogleCalendarAutoSyncLoop();
        return;
      }

      await runGoogleCalendarSync(allowInteractive: false);
    } catch (_) {
    } finally {
      _googleCalendarSyncInFlight = false;
    }
  }

  static Future<void> startGoogleCalendarAutoSyncIfEnabled() async {
    await stopGoogleCalendarAutoSyncLoop();

    final connected = await PreferencesService.isGoogleCalendarConnected();
    final autoSyncEnabled = await PreferencesService.isAutoSyncEnabled();
    if (!connected || !autoSyncEnabled) {
      return;
    }

    final status = await getGoogleCalendarSyncStatus();
    if (status['success'] == true) {
      final backendEnabled = status['auto_sync_enabled'] == true;
      if (!backendEnabled) {
        return;
      }
      final interval = (status['sync_interval_minutes'] as num?)?.toInt() ?? 5;
      _googleCalendarSyncInterval = Duration(minutes: interval.clamp(1, 60));
    } else {
      _googleCalendarSyncInterval = const Duration(minutes: 5);
    }

    await _runGoogleCalendarAutoSyncTick();
    _googleCalendarSyncTimer = Timer.periodic(
      _googleCalendarSyncInterval,
      (_) {
        unawaited(_runGoogleCalendarAutoSyncTick());
      },
    );
  }

  static Future<void> stopGoogleCalendarAutoSyncLoop() async {
    _googleCalendarSyncTimer?.cancel();
    _googleCalendarSyncTimer = null;
    _googleCalendarSyncInFlight = false;
  }

  static Future<Map<String, dynamic>> createGoogleCalendarFocusEvent() async {
    try {
      final appToken = await PreferencesService.getAuthToken();
      if (appToken == null || appToken.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final googleAccessToken = await _ensureCalendarAccessToken();
      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        return {'success': false, 'message': 'Google Calendar authorization required'};
      }

      final start = DateTime.now().add(const Duration(minutes: 15));
      final end = start.add(const Duration(minutes: 30));
      final response = await http.post(
        Uri.parse('$baseUrl/integrations/google-calendar/events/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
        body: jsonEncode({
          'access_token': googleAccessToken,
          'summary': 'Calm Clarity Focus Session',
          'description': 'A mindful check-in session generated from Calm Clarity.',
          'start_iso': start.toUtc().toIso8601String(),
          'end_iso': end.toUtc().toIso8601String(),
          'timezone': 'UTC',
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'event': Map<String, dynamic>.from(data),
        };
      }

      return {'success': false, 'message': data['detail'] ?? 'Failed to create event'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'reset_token': data['reset_token'],
          'reset_link': data['reset_link'],
          'delivery': data['delivery'],
        };
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Request failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'new_password': newPassword,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Reset failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<bool> refreshToken() async {
    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await PreferencesService.setAuthToken(data['access_token']);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() async {
    await stopGoogleCalendarAutoSyncLoop();
    await PreferencesService.setAuthToken('');
    await PreferencesService.setUserName('');
    await PreferencesService.setUserEmail('');
  }
}
