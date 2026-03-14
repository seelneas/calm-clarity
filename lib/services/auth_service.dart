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
    defaultValue: String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: ''),
  );
  static const String _adminApiKey = String.fromEnvironment(
    'ADMIN_API_KEY',
    defaultValue: '',
  );

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb && googleWebClientId.isNotEmpty ? googleWebClientId : null,
    scopes: ['email', 'profile'],
  );

  static final GoogleSignIn _googleCalendarSignIn = GoogleSignIn(
    clientId: kIsWeb && googleWebClientId.isNotEmpty ? googleWebClientId : null,
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

  static Map<String, dynamic> _errorResultFromResponse(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = _tryDecodeJson(response.body);
    final detail = _extractDetailMessage(body, fallbackMessage);
    return {
      'success': false,
      'message': detail,
      'status_code': response.statusCode,
      'error_type': _classifyAuthError(detail, response.statusCode),
    };
  }

  static dynamic _tryDecodeJson(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
  }

  static String _extractDetailMessage(dynamic body, String fallbackMessage) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      final message = body['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return fallbackMessage;
  }

  static String _classifyAuthError(String message, int statusCode) {
    final lowered = message.toLowerCase();
    if (lowered.contains('account is suspended')) {
      return 'account_suspended';
    }
    if (lowered.contains('too many failed attempts') ||
        lowered.contains('captcha required') ||
        lowered.contains('rate limit exceeded')) {
      return 'account_locked';
    }
    if (lowered.contains('admin mfa')) {
      return 'mfa_required';
    }
    if (lowered.contains('could not validate credentials') ||
        lowered.contains('incorrect email or password')) {
      return 'invalid_credentials';
    }
    if (statusCode == 401) {
      return 'unauthorized';
    }
    if (statusCode == 403) {
      return 'forbidden';
    }
    return 'unknown';
  }

  static Future<Map<String, String>> _buildAuthHeaders({
    bool requireAuthToken = false,
    bool includeAdminKey = false,
    String? adminTotp,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (requireAuthToken) {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) {
        throw Exception('Sign in required');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    if (includeAdminKey && _adminApiKey.trim().isNotEmpty) {
      headers['X-Admin-Key'] = _adminApiKey.trim();
    }
    final trimmedTotp = (adminTotp ?? '').trim();
    if (trimmedTotp.isNotEmpty) {
      headers['X-Admin-TOTP'] = trimmedTotp;
    }
    return headers;
  }

  static Future<Map<String, dynamic>> signup(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(Map<String, dynamic>.from(data as Map));
        return {'success': true};
      } else {
        return _errorResultFromResponse(response, 'Signup failed');
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(Map<String, dynamic>.from(data as Map));
        return {'success': true};
      } else {
        return _errorResultFromResponse(response, 'Login failed');
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<void> _handleAuthSuccess(Map<String, dynamic> data) async {
    final token = (data['access_token'] ?? '').toString();
    final user = Map<String, dynamic>.from((data['user'] as Map?) ?? const {});
    final email = (user['email'] ?? '').toString().trim().toLowerCase();
    final resolvedName = (user['name'] ?? '').toString().trim();
    final role = (user['role'] ?? 'user').toString().trim().toLowerCase();
    final photoUrl = (user['profile_photo_url'] ?? '').toString().trim();
    await PreferencesService.setAuthToken(token);
    await PreferencesService.setUserName(resolvedName);
    await PreferencesService.setUserEmail(email);
    await PreferencesService.setUserRole(role);
    if (photoUrl.isNotEmpty) {
      await PreferencesService.setProfilePhotoPath(photoUrl);
    }
  }

  static Future<Map<String, dynamic>> syncCurrentUserProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: await _buildAuthHeaders(requireAuthToken: true),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        return _errorResultFromResponse(
          response,
          'Failed to fetch user profile',
        );
      }

      final email = (data['email'] ?? '').toString().trim().toLowerCase();
      final name = (data['name'] ?? '').toString().trim();
      final role = (data['role'] ?? 'user').toString().trim().toLowerCase();
      final photoUrl = (data['profile_photo_url'] ?? '').toString().trim();
      if (email.isNotEmpty) {
        await PreferencesService.setUserEmail(email);
      }
      await PreferencesService.setUserName(name);
      await PreferencesService.setUserRole(role);
      if (photoUrl.isNotEmpty) {
        await PreferencesService.setProfilePhotoPath(photoUrl);
      }
      return {'success': true, 'user': data};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
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
      if (googleUser == null)
        return {'success': false, 'message': 'Sign in cancelled'};

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      final String? accessToken = googleAuth.accessToken;

      if ((idToken == null || idToken.isEmpty) &&
          (accessToken == null || accessToken.isEmpty)) {
        return {
          'success': false,
          'message':
              'Failed to get Google token. Check OAuth configuration and try again.',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({
          'token': idToken ?? '',
          'access_token': accessToken ?? '',
          'email': googleUser.email,
          'name': googleUser.displayName ?? '',
          'provider': 'google',
        }),
      );

      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200) {
        await _handleAuthSuccess(Map<String, dynamic>.from(data as Map));
        return {'success': true};
      } else {
        return _errorResultFromResponse(response, 'Google login failed');
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return {
        'success': false,
        'message': 'Google Sign-In Error: ${e.toString().split('\n').first}',
      };
    }
  }

  static Future<Map<String, dynamic>> updateIntegrations(
    String email,
    bool google,
    bool apple,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(
          '$baseUrl/update_integrations?email=$email&google=${google ? 1 : 0}&apple=${apple ? 1 : 0}',
        ),
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
        return {
          'success': false,
          'message': 'Google Calendar authorization cancelled',
        };
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

      return {
        'success': false,
        'message': data['detail'] ?? 'Google Calendar connection failed',
      };
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
        return {
          'success': true,
          'message': data['message'] ?? 'Google Calendar disconnected',
        };
      }

      return {
        'success': false,
        'message': data['detail'] ?? 'Disconnect failed',
      };
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
        return {
          'success': false,
          'message': 'Google Calendar authorization required',
        };
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

      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to fetch events',
      };
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
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to fetch sync status',
      };
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
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to update sync settings',
      };
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
        return {
          'success': false,
          'message': 'Google Calendar authorization required',
        };
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
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to run calendar sync',
      };
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
    _googleCalendarSyncTimer = Timer.periodic(_googleCalendarSyncInterval, (_) {
      unawaited(_runGoogleCalendarAutoSyncTick());
    });
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
        return {
          'success': false,
          'message': 'Google Calendar authorization required',
        };
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
          'description':
              'A mindful check-in session generated from Calm Clarity.',
          'start_iso': start.toUtc().toIso8601String(),
          'end_iso': end.toUtc().toIso8601String(),
          'timezone': 'UTC',
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'event': Map<String, dynamic>.from(data)};
      }

      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to create event',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: await _buildAuthHeaders(),
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
        return {
          'success': false,
          'message': data['detail'] ?? 'Request failed',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({'token': token, 'new_password': newPassword}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return _errorResultFromResponse(response, 'Reset failed');
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> adminMfaSetup({String? adminTotp}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/mfa/setup'),
        headers: await _buildAuthHeaders(
          requireAuthToken: true,
          includeAdminKey: true,
          adminTotp: adminTotp,
        ),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(data)};
      }
      return _errorResultFromResponse(response, 'Unable to load MFA setup');
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> adminMfaEnable(
    String code, {
    String? adminTotp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/mfa/enable'),
        headers: await _buildAuthHeaders(
          requireAuthToken: true,
          includeAdminKey: true,
          adminTotp: adminTotp,
        ),
        body: jsonEncode({'code': code}),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': true,
          'message': data['message'] ?? 'Admin MFA enabled',
          'mfa_enabled': data['mfa_enabled'] == true,
        };
      }
      return _errorResultFromResponse(response, 'Unable to enable MFA');
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> adminMfaDisable(
    String code, {
    String? adminTotp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/mfa/disable'),
        headers: await _buildAuthHeaders(
          requireAuthToken: true,
          includeAdminKey: true,
          adminTotp: adminTotp,
        ),
        body: jsonEncode({'code': code}),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': true,
          'message': data['message'] ?? 'Admin MFA disabled',
          'mfa_enabled': data['mfa_enabled'] == true,
        };
      }
      return _errorResultFromResponse(response, 'Unable to disable MFA');
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> fetchActiveSessions() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/active'),
        headers: await _buildAuthHeaders(requireAuthToken: true),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(data)};
      }
      return _errorResultFromResponse(
        response,
        'Failed to load active sessions',
      );
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> revokeSession(int sessionId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/sessions/active/$sessionId'),
        headers: await _buildAuthHeaders(requireAuthToken: true),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': true,
          'message': data['message'] ?? 'Session revoked',
        };
      }
      return _errorResultFromResponse(response, 'Failed to revoke session');
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> revokeAllSessions() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sessions/active/revoke-all'),
        headers: await _buildAuthHeaders(requireAuthToken: true),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': true,
          'message': data['message'] ?? 'All sessions revoked',
        };
      }
      return _errorResultFromResponse(
        response,
        'Failed to revoke all sessions',
      );
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/change-password'),
        headers: await _buildAuthHeaders(requireAuthToken: true),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
      final data = _tryDecodeJson(response.body);
      if (response.statusCode == 200 && data is Map) {
        await logout();
        return {
          'success': true,
          'message': data['message'] ?? 'Password changed successfully',
          'global_logout': true,
        };
      }
      return _errorResultFromResponse(response, 'Failed to change password');
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
