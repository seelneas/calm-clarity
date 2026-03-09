import 'dart:convert';

import 'package:calm_clarity/services/ai_admin_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    AIAdminService.setAuthTokenForTesting('test-token');
  });

  tearDown(() {
    AIAdminService.resetHttpClient();
    AIAdminService.clearAuthTokenForTesting();
  });

  test(
    'fetchObservabilityDashboard returns parsed dashboard payload',
    () async {
      AIAdminService.setHttpClientForTesting(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.url.path, '/admin/observability/dashboard');
          return http.Response(
            jsonEncode({
              'generated_at': '2026-03-07T12:00:00Z',
              'service_status': 'healthy',
              'traffic': {
                'window_seconds': 900,
                'request_count': 22,
                'error_count': 1,
                'error_rate': 0.04,
                'requests_per_second': 0.2,
                'latency_p50_ms': 80.0,
                'latency_p95_ms': 130.0,
                'latency_avg_ms': 95.5,
                'top_paths': [
                  {'path': '/login', 'count': 8},
                ],
              },
              'ai_queue_depth': 2,
              'ai_failed_registry': 0,
              'notification_recent_failed': 0,
              'notification_recent_sent': 5,
              'signals': [],
            }),
            200,
          );
        }),
      );

      final result = await AIAdminService.fetchObservabilityDashboard();

      expect(result['success'], isTrue);
      final data = result['data'] as Map<String, dynamic>;
      expect(data['service_status'], 'healthy');
      expect((data['traffic'] as Map<String, dynamic>)['request_count'], 22);
    },
  );

  test('fetchObservabilityAlerts returns API detail on error', () async {
    AIAdminService.setHttpClientForTesting(
      MockClient(
        (_) async =>
            http.Response(jsonEncode({'detail': 'Admin access denied'}), 403),
      ),
    );

    final result = await AIAdminService.fetchObservabilityAlerts();

    expect(result['success'], isFalse);
    expect(result['message'], 'Admin access denied');
  });

  test('fetchObservabilityMetrics returns raw text payload', () async {
    AIAdminService.setHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/admin/observability/metrics');
        return http.Response(
          'calm_clarity_http_requests_total 12\ncalm_clarity_http_errors_total 0\n',
          200,
        );
      }),
    );

    final result = await AIAdminService.fetchObservabilityMetrics();

    expect(result['success'], isTrue);
    expect(
      (result['data'] as String).contains('calm_clarity_http_requests_total'),
      isTrue,
    );
  });
}
