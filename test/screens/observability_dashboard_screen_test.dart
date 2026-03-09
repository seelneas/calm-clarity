import 'dart:convert';

import 'package:calm_clarity/screens/observability_dashboard_screen.dart';
import 'package:calm_clarity/services/ai_admin_service.dart';
import 'package:calm_clarity/theme.dart';
import 'package:flutter/material.dart';
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

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getDarkTheme(1.0),
        home: const ObservabilityDashboardScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('renders overview cards and switches tabs', (tester) async {
    AIAdminService.setHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/dashboard')) {
          return http.Response(
            jsonEncode({
              'generated_at': '2026-03-07T12:00:00Z',
              'service_status': 'healthy',
              'traffic': {
                'window_seconds': 900,
                'request_count': 42,
                'error_count': 2,
                'error_rate': 0.047,
                'requests_per_second': 0.11,
                'latency_p50_ms': 66.3,
                'latency_p95_ms': 123.4,
                'latency_avg_ms': 80.2,
                'top_paths': [
                  {'path': '/login', 'count': 10},
                ],
              },
              'ai_queue_depth': 1,
              'ai_failed_registry': 0,
              'notification_recent_failed': 0,
              'notification_recent_sent': 3,
              'signals': [
                {
                  'signal': 'http_error_rate_warn',
                  'severity': 'warn',
                  'detail': 'HTTP error rate=4.70%',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/alerts')) {
          return http.Response(
            jsonEncode({
              'generated_at': '2026-03-07T12:00:00Z',
              'overall_status': 'warn',
              'alerts': [
                {
                  'name': 'http_error_rate',
                  'status': 'warn',
                  'detail': 'error_rate=4.70%',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/metrics')) {
          return http.Response(
            'calm_clarity_http_requests_total 42\ncalm_clarity_http_errors_total 2\n',
            200,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await pumpDashboard(tester);

    expect(find.text('Observability Dashboard'), findsOneWidget);
    expect(find.text('Service Status'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('Traffic & Latency'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Overall Alert State'), findsOneWidget);
    expect(find.text('http_error_rate'), findsOneWidget);

    await tester.tap(find.text('Metrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Prometheus Metrics Snapshot'), findsOneWidget);
    expect(
      find.textContaining('calm_clarity_http_requests_total'),
      findsWidgets,
    );
  });

  testWidgets('shows retry UI when all endpoints fail', (tester) async {
    AIAdminService.setHttpClientForTesting(
      MockClient((_) async => http.Response('gateway timeout', 504)),
    );

    await pumpDashboard(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Failed to load observability'), findsWidgets);
  });
}
