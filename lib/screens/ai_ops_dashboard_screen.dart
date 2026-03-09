import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/ai_admin_service.dart';

class AIOpsDashboardScreen extends StatefulWidget {
  const AIOpsDashboardScreen({super.key});

  @override
  State<AIOpsDashboardScreen> createState() => _AIOpsDashboardScreenState();
}

class _AIOpsDashboardScreenState extends State<AIOpsDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await AIAdminService.fetchDashboard();
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _data = Map<String, dynamic>.from(result['data'] as Map);
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _error = (result['message'] ?? 'Unable to fetch dashboard').toString();
      _isLoading = false;
    });
  }

  int _readInt(Map<String, dynamic>? source, String key) {
    final value = source?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    final queue = _data?['queue_depth'] is Map
        ? Map<String, dynamic>.from(_data!['queue_depth'] as Map)
        : <String, dynamic>{};
    final jobs = _data?['job_status'] is Map
        ? Map<String, dynamic>.from(_data!['job_status'] as Map)
        : <String, dynamic>{};
    final retries = _data?['retries'] is Map
        ? Map<String, dynamic>.from(_data!['retries'] as Map)
        : <String, dynamic>{};
    final moderation = _data?['moderation'] is Map
        ? Map<String, dynamic>.from(_data!['moderation'] as Map)
        : <String, dynamic>{};
    final quota = _data?['quota'] is Map
        ? Map<String, dynamic>.from(_data!['quota'] as Map)
        : <String, dynamic>{};
    final failedJobs = _data?['failed_jobs'] is List
        ? List<Map<String, dynamic>>.from(
            (_data!['failed_jobs'] as List)
                .whereType<Map>()
                .map((job) => Map<String, dynamic>.from(job)),
          )
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI Ops Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle(context, 'Queue Depth'),
                    _metricsRow(context, [
                      _metricCard(context, 'Queued', _readInt(queue, 'queued_count').toString()),
                      _metricCard(context, 'Started', _readInt(queue, 'started_count').toString()),
                      _metricCard(context, 'Failed Reg', _readInt(queue, 'failed_registry_count').toString()),
                    ]),
                    const SizedBox(height: 16),
                    _sectionTitle(context, 'Jobs'),
                    _metricsRow(context, [
                      _metricCard(context, 'Total', _readInt(jobs, 'total').toString()),
                      _metricCard(context, 'Completed', _readInt(jobs, 'completed').toString()),
                      _metricCard(context, 'Failed', _readInt(jobs, 'failed').toString()),
                      _metricCard(context, 'Blocked', _readInt(jobs, 'blocked').toString()),
                    ]),
                    const SizedBox(height: 16),
                    _sectionTitle(context, 'Retries & Moderation'),
                    _metricsRow(context, [
                      _metricCard(context, 'Retried Jobs', _readInt(retries, 'jobs_with_retry').toString()),
                      _metricCard(context, 'Retry Attempts', _readInt(retries, 'total_retry_attempts').toString()),
                      _metricCard(context, 'Exhausted', _readInt(retries, 'exhausted_jobs').toString()),
                      _metricCard(context, 'Moderation Hits', _readInt(moderation, 'blocked_requests').toString()),
                    ]),
                    const SizedBox(height: 16),
                    _sectionTitle(context, 'Quota Usage'),
                    _metricsRow(context, [
                      _metricCard(context, 'Daily Limit', _readInt(quota, 'daily_quota_limit').toString()),
                      _metricCard(context, 'Today', _readInt(quota, 'today_request_count').toString()),
                      _metricCard(context, 'Today Users', _readInt(quota, 'today_unique_users').toString()),
                      _metricCard(context, 'Window', _readInt(quota, 'window_request_count').toString()),
                    ]),
                    const SizedBox(height: 20),
                    _sectionTitle(context, 'Recent Failed Jobs'),
                    if (failedJobs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.subtleBorder),
                        ),
                        child: const Text('No failed jobs in current window.'),
                      )
                    else
                      ...failedJobs.map(
                        (job) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.subtleBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (job['job_id'] ?? '').toString(),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Type: ${(job['job_type'] ?? 'n/a')}  •  Attempts: ${(job['attempts'] ?? 0)}/${(job['max_attempts'] ?? 0)}',
                                style: TextStyle(color: colors.textMuted, fontSize: 12),
                              ),
                              if ((job['error_message'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  (job['error_message'] ?? '').toString(),
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _metricsRow(BuildContext context, List<Widget> children) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: children,
    );
  }

  Widget _metricCard(BuildContext context, String label, String value) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      width: 160,
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ],
      ),
    );
  }
}
