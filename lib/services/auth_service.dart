import 'dart:convert';
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
    await PreferencesService.setAuthToken('');
    await PreferencesService.setUserName('');
    await PreferencesService.setUserEmail('');
  }
}
