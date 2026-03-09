import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai_admin_service.dart';
import '../theme.dart';

class ObservabilityDashboardScreen extends StatefulWidget {
  const ObservabilityDashboardScreen({super.key});

  @override
  State<ObservabilityDashboardScreen> createState() =>
      _ObservabilityDashboardScreenState();
}

class _ObservabilityDashboardScreenState
    extends State<ObservabilityDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _alerts;
  String _metricsRaw = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadAll(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final results = await Future.wait([
      AIAdminService.fetchObservabilityDashboard(),
      AIAdminService.fetchObservabilityAlerts(),
      AIAdminService.fetchObservabilityMetrics(),
    ]);

    if (!mounted) return;

    final dashboardResult = results[0];
    final alertsResult = results[1];
    final metricsResult = results[2];

    final failures = <String>[];
    if (dashboardResult['success'] != true) {
      failures.add(
        (dashboardResult['message'] ?? 'Dashboard unavailable').toString(),
      );
    }
    if (alertsResult['success'] != true) {
      failures.add(
        (alertsResult['message'] ?? 'Alerts unavailable').toString(),
      );
    }
    if (metricsResult['success'] != true) {
      failures.add(
        (metricsResult['message'] ?? 'Metrics unavailable').toString(),
      );
    }

    if (failures.length == 3) {
      setState(() {
        _isLoading = false;
        _error = failures.join('\n');
      });
      return;
    }

    setState(() {
      _dashboard = dashboardResult['success'] == true
          ? Map<String, dynamic>.from(
              dashboardResult['data'] as Map<String, dynamic>,
            )
          : _dashboard;
      _alerts = alertsResult['success'] == true
          ? Map<String, dynamic>.from(
              alertsResult['data'] as Map<String, dynamic>,
            )
          : _alerts;
      if (metricsResult['success'] == true) {
        _metricsRaw = (metricsResult['data'] ?? '').toString();
      }
      _error = failures.isEmpty ? null : failures.join('\n');
      _isLoading = false;
    });
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return 0;
  }

  String _readStatusText() {
    final status = (_dashboard?['service_status'] ?? 'unknown').toString();
    return status.toUpperCase();
  }

  Color _statusColor(BuildContext context, String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'critical' || normalized == 'fail') {
      return Colors.redAccent;
    }
    if (normalized == 'degraded' || normalized == 'warn') {
      return Colors.orangeAccent;
    }
    if (normalized == 'healthy' || normalized == 'ok') {
      return Colors.greenAccent.shade400;
    }
    return Theme.of(context).extension<AppColors>()!.textMuted;
  }

  List<MapEntry<String, String>> _parsedMetrics() {
    if (_metricsRaw.trim().isEmpty) return const [];
    final entries = <MapEntry<String, String>>[];
    final lines = _metricsRaw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'));

    for (final line in lines) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts.sublist(0, parts.length - 1).join(' ');
      final value = parts.last;
      entries.add(MapEntry(name, value));
    }

    return entries;
  }

  String _friendlyDateTime(String rawIso) {
    if (rawIso.trim().isEmpty) return 'n/a';
    final parsed = DateTime.tryParse(rawIso);
    if (parsed == null) return rawIso;
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Observability Dashboard'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _isLoading ? null : () => _loadAll(),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Alerts'),
              Tab(text: 'Metrics'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _dashboard == null && _alerts == null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadAll,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _loadAll,
                    child: _buildOverview(context),
                  ),
                  RefreshIndicator(
                    onRefresh: _loadAll,
                    child: _buildAlerts(context),
                  ),
                  RefreshIndicator(
                    onRefresh: _loadAll,
                    child: _buildMetrics(context),
                  ),
                ],
              ),
        bottomNavigationBar: _error == null
            ? null
            : Container(
                color: colors.cardBackground,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
                ),
              ),
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final traffic = _dashboard?['traffic'] is Map
        ? Map<String, dynamic>.from(_dashboard!['traffic'] as Map)
        : <String, dynamic>{};
    final topPaths = traffic['top_paths'] is List
        ? List<Map<String, dynamic>>.from(
            (traffic['top_paths'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];
    final signals = _dashboard?['signals'] is List
        ? List<Map<String, dynamic>>.from(
            (_dashboard!['signals'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];

    final serviceStatus = (_dashboard?['service_status'] ?? 'unknown')
        .toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          context,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Status',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _readStatusText(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _statusColor(context, serviceStatus),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_friendlyDateTime((_dashboard?['generated_at'] ?? '').toString())}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.monitor_heart,
                color: _statusColor(context, serviceStatus),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Traffic & Latency'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metricCard(
              context,
              'Requests (window)',
              _toInt(traffic['request_count']).toString(),
            ),
            _metricCard(
              context,
              'Errors (window)',
              _toInt(traffic['error_count']).toString(),
            ),
            _metricCard(
              context,
              'Error Rate',
              '${(_toDouble(traffic['error_rate']) * 100).toStringAsFixed(2)}%',
            ),
            _metricCard(
              context,
              'Req/s',
              _toDouble(traffic['requests_per_second']).toStringAsFixed(2),
            ),
            _metricCard(
              context,
              'Latency p50',
              '${_toDouble(traffic['latency_p50_ms']).toStringAsFixed(1)} ms',
            ),
            _metricCard(
              context,
              'Latency p95',
              '${_toDouble(traffic['latency_p95_ms']).toStringAsFixed(1)} ms',
            ),
            _metricCard(
              context,
              'Latency avg',
              '${_toDouble(traffic['latency_avg_ms']).toStringAsFixed(1)} ms',
            ),
            _metricCard(
              context,
              'Window',
              '${_toInt(traffic['window_seconds'])} s',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('AI & Notifications'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metricCard(
              context,
              'AI Queue Depth',
              _toInt(_dashboard?['ai_queue_depth']).toString(),
            ),
            _metricCard(
              context,
              'AI Failed Registry',
              _toInt(_dashboard?['ai_failed_registry']).toString(),
            ),
            _metricCard(
              context,
              'Notif Sent (recent)',
              _toInt(_dashboard?['notification_recent_sent']).toString(),
            ),
            _metricCard(
              context,
              'Notif Failed (recent)',
              _toInt(_dashboard?['notification_recent_failed']).toString(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('Top Paths'),
        _panel(
          context,
          child: topPaths.isEmpty
              ? Text(
                  'No path data captured yet.',
                  style: TextStyle(color: colors.textMuted),
                )
              : Column(
                  children: topPaths.map((pathItem) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (pathItem['path'] ?? '').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _toInt(pathItem['count']).toString(),
                            style: TextStyle(color: colors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Incident Signals'),
        _panel(
          context,
          child: signals.isEmpty
              ? const Text('No active incident signals. System appears stable.')
              : Column(
                  children: signals.map((signal) {
                    final severity = (signal['severity'] ?? 'info').toString();
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceOverlay,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.subtleBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: _statusColor(context, severity),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (signal['signal'] ?? 'signal').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (signal['detail'] ?? '').toString(),
                                  style: TextStyle(color: colors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAlerts(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final items = _alerts?['alerts'] is List
        ? List<Map<String, dynamic>>.from(
            (_alerts!['alerts'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];

    final overall = (_alerts?['overall_status'] ?? 'unknown').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          context,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Alert State',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      overall.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(context, overall),
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_friendlyDateTime((_alerts?['generated_at'] ?? '').toString())}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.notifications_active,
                color: _statusColor(context, overall),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _panel(
            context,
            child: Text(
              'No alert checks returned.',
              style: TextStyle(color: colors.textMuted),
            ),
          )
        else
          ...items.map((alert) {
            final status = (alert['status'] ?? 'unknown').toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.subtleBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(context, status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (alert['name'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: _statusColor(context, status),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (alert['detail'] ?? '').toString(),
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final entries = _parsedMetrics();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Prometheus Metrics Snapshot',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Raw backend metric stream from /admin/observability/metrics',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          _panel(
            context,
            child: Text(
              _metricsRaw.trim().isEmpty
                  ? 'No metrics available right now.'
                  : 'Unable to parse metrics payload.',
              style: TextStyle(color: colors.textMuted),
            ),
          )
        else
          ...entries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.subtleBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(entry.value, style: TextStyle(color: colors.textMuted)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        _panel(
          context,
          child: SelectableText(
            _metricsRaw.trim().isEmpty ? 'n/a' : _metricsRaw.trim(),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }

  Widget _metricCard(BuildContext context, String label, String value) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      width: 164,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
