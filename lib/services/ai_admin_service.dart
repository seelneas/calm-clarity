import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'preferences_service.dart';

class AIAdminService {
  static const String _adminApiKey = String.fromEnvironment(
    'ADMIN_API_KEY',
    defaultValue: '',
  );
  static http.Client _httpClient = http.Client();
  static String? _testAuthToken;

  static void setHttpClientForTesting(http.Client client) {
    _httpClient = client;
  }

  static void resetHttpClient() {
    _httpClient = http.Client();
  }

  static void setAuthTokenForTesting(String token) {
    _testAuthToken = token;
  }

  static void clearAuthTokenForTesting() {
    _testAuthToken = null;
  }

  static Future<Map<String, dynamic>> fetchDashboard({
    int days = 7,
    int failedLimit = 20,
  }) async {
    try {
      final uri = Uri.parse(
        '${AuthService.baseUrl}/admin/ai/ops/dashboard?days=$days&failed_limit=$failedLimit',
      );
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load AI ops dashboard');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchUserSummary() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/summary');
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load admin user summary');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchUsers({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final encodedQuery = Uri.encodeQueryComponent(query);
      final uri = Uri.parse(
        '${AuthService.baseUrl}/admin/users?query=$encodedQuery&limit=$limit&offset=$offset',
      );
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load users');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId');
      final response = await _httpClient.delete(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to delete user');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> suspendUser(int userId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId/suspend');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to suspend user');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> reactivateUser(int userId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId/reactivate');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to reactivate user');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> checkAdminAccess() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/access');
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'is_admin': true};
      }

      String message = 'Admin access denied';
      if (response.body.isNotEmpty) {
        try {
          final parsed = jsonDecode(response.body);
          if (parsed is Map && parsed['detail'] != null) {
            message = parsed['detail'].toString();
          }
        } catch (_) {}
      }

      return {'success': false, 'is_admin': false, 'message': message};
    } catch (error) {
      return {'success': false, 'is_admin': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchObservabilityDashboard() async {
    try {
      final uri = Uri.parse(
        '${AuthService.baseUrl}/admin/observability/dashboard',
      );
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(
        response,
        'Failed to load observability dashboard',
      );
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchObservabilityAlerts() async {
    try {
      final uri = Uri.parse(
        '${AuthService.baseUrl}/admin/observability/alerts',
      );
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(
        response,
        'Failed to load observability alerts',
      );
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchObservabilityMetrics() async {
    try {
      final uri = Uri.parse(
        '${AuthService.baseUrl}/admin/observability/metrics',
      );
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': response.body};
      }

      String message = 'Failed to load observability metrics';
      if (response.body.isNotEmpty) {
        try {
          final parsed = jsonDecode(response.body);
          if (parsed is Map && parsed['detail'] != null) {
            message = parsed['detail'].toString();
          }
        } catch (_) {}
      }

      return {'success': false, 'message': message};
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, String>> _buildAdminHeaders() async {
    final token = _testAuthToken ?? await PreferencesService.getAuthToken();
    if (token == null || token.isEmpty) {
      throw Exception('Sign in required');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (_adminApiKey.trim().isNotEmpty) {
      headers['X-Admin-Key'] = _adminApiKey.trim();
    }
    return headers;
  }

  static Map<String, dynamic> _decodeJsonResponse(
    http.Response response,
    String fallbackMessage,
  ) {
    final body = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

    if (response.statusCode == 200) {
      return {'success': true, 'data': Map<String, dynamic>.from(body as Map)};
    }

    return {
      'success': false,
      'message': (body is Map && body['detail'] != null)
          ? body['detail'].toString()
          : fallbackMessage,
    };
  }
}
