@Timeout(Duration(minutes: 20))
import 'dart:convert';

import 'package:calm_clarity/screens/observability_dashboard_screen.dart';
import 'package:calm_clarity/services/ai_admin_service.dart';
import 'package:calm_clarity/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'integration-token'});
    AIAdminService.setAuthTokenForTesting('integration-token');
  });

  tearDown(() {
    AIAdminService.resetHttpClient();
    AIAdminService.clearAuthTokenForTesting();
  });

  testWidgets('observability journey: overview -> alerts -> metrics', (
    tester,
  ) async {
    AIAdminService.setHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/dashboard')) {
          return http.Response(
            jsonEncode({
              'generated_at': '2026-03-07T12:00:00Z',
              'service_status': 'degraded',
              'traffic': {
                'window_seconds': 900,
                'request_count': 120,
                'error_count': 9,
                'error_rate': 0.075,
                'requests_per_second': 0.5,
                'latency_p50_ms': 91.3,
                'latency_p95_ms': 520.5,
                'latency_avg_ms': 142.2,
                'top_paths': [
                  {'path': '/admin/observability/dashboard', 'count': 15},
                  {'path': '/login', 'count': 14},
                ],
              },
              'ai_queue_depth': 6,
              'ai_failed_registry': 2,
              'notification_recent_failed': 1,
              'notification_recent_sent': 11,
              'signals': [
                {
                  'signal': 'http_error_rate_warn',
                  'severity': 'warn',
                  'detail': 'HTTP error rate=7.50%',
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
                  'detail': 'error_rate=7.50%',
                },
                {
                  'name': 'http_latency_p95',
                  'status': 'ok',
                  'detail': 'p95=520ms',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/metrics')) {
          return http.Response(
            'calm_clarity_http_requests_total 120\ncalm_clarity_http_errors_total 9\n',
            200,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const <ThemeExtension<dynamic>>[
            AppColors.dark,
          ],
        ),
        home: const ObservabilityDashboardScreen(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Service Status'), findsOneWidget);
    expect(find.text('DEGRADED'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Overall Alert State'), findsOneWidget);
    expect(find.text('WARN'), findsWidgets);

    await tester.tap(find.text('Metrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Prometheus Metrics Snapshot'), findsOneWidget);
    expect(
      find.textContaining('calm_clarity_http_requests_total'),
      findsWidgets,
    );
  });
}
