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
  static String? _adminTotpCode;
  static String? _adminRecoveryCode;
  static String? _adminStepUpToken;

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

  static void setAdminTotpCode(String code) {
    final value = code.trim();
    _adminTotpCode = value.isEmpty ? null : value;
  }

  static void clearAdminTotpCode() {
    _adminTotpCode = null;
  }

  static void setAdminRecoveryCode(String code) {
    final value = code.trim();
    _adminRecoveryCode = value.isEmpty ? null : value;
  }

  static void clearAdminRecoveryCode() {
    _adminRecoveryCode = null;
  }

  static void setAdminStepUpToken(String token) {
    final value = token.trim();
    _adminStepUpToken = value.isEmpty ? null : value;
  }

  static void clearAdminStepUpToken() {
    _adminStepUpToken = null;
  }

  static Future<Map<String, dynamic>> performAdminReauth({
    required String password,
    String? mfaCode,
    String? recoveryCode,
  }) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/re-auth');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
        body: jsonEncode({
          'password': password,
          if ((mfaCode ?? '').trim().isNotEmpty) 'mfa_code': mfaCode!.trim(),
          if ((recoveryCode ?? '').trim().isNotEmpty)
            'recovery_code': recoveryCode!.trim(),
        }),
      );

      final decoded = _decodeJsonResponse(response, 'Admin re-auth failed');
      if (decoded['success'] == true) {
        final data = Map<String, dynamic>.from(decoded['data'] as Map);
        final token = (data['step_up_token'] ?? '').toString();
        if (token.isNotEmpty) {
          setAdminStepUpToken(token);
        }
      }
      return decoded;
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchRecoveryCodesStatus() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/mfa/recovery-codes/status');
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load recovery code status');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> regenerateRecoveryCodes() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/mfa/recovery-codes/regenerate');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to regenerate recovery codes');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> fetchAdminMfaSetup() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/mfa/setup');
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load MFA setup');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> enableAdminMfa(String code) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/mfa/enable');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
        body: jsonEncode({'code': code}),
      );
      return _decodeJsonResponse(response, 'Failed to enable admin MFA');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> disableAdminMfa(String code) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/mfa/disable');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
        body: jsonEncode({'code': code}),
      );
      return _decodeJsonResponse(response, 'Failed to disable admin MFA');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
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

  static Future<Map<String, dynamic>> fetchUserSessions(int userId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId/sessions');
      final response = await _httpClient.get(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to load user sessions');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> revokeUserSession(int userId, int sessionId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId/sessions/$sessionId');
      final response = await _httpClient.delete(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to revoke session');
    } catch (error) {
      return {'success': false, 'message': 'Connection error: $error'};
    }
  }

  static Future<Map<String, dynamic>> revokeAllUserSessions(int userId) async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/admin/users/$userId/sessions/revoke-all');
      final response = await _httpClient.post(
        uri,
        headers: await _buildAdminHeaders(),
      );
      return _decodeJsonResponse(response, 'Failed to revoke all sessions');
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
    if ((_adminTotpCode ?? '').trim().isNotEmpty) {
      headers['X-Admin-TOTP'] = _adminTotpCode!.trim();
    }
    if ((_adminRecoveryCode ?? '').trim().isNotEmpty) {
      headers['X-Admin-Recovery-Code'] = _adminRecoveryCode!.trim();
    }
    if ((_adminStepUpToken ?? '').trim().isNotEmpty) {
      headers['X-Admin-Reauth'] = _adminStepUpToken!.trim();
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

    final detail = (body is Map && body['detail'] != null)
        ? body['detail'].toString()
        : fallbackMessage;
    final lowered = detail.toLowerCase();
    final requiresReauth = response.statusCode == 403 && lowered.contains('re-auth required');
    if (requiresReauth) {
      clearAdminStepUpToken();
    }

    return {
      'success': false,
      'message': detail,
      'status_code': response.statusCode,
      'requires_mfa': response.statusCode == 403 && lowered.contains('mfa'),
      'mfa_not_configured': response.statusCode == 403 && lowered.contains('not configured'),
      'requires_reauth': requiresReauth,
    };
  }
}
