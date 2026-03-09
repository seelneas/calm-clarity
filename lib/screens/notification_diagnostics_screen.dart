import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme.dart';

class NotificationDiagnosticsScreen extends StatefulWidget {
  const NotificationDiagnosticsScreen({super.key});

  @override
  State<NotificationDiagnosticsScreen> createState() =>
      _NotificationDiagnosticsScreenState();
}

class _NotificationDiagnosticsScreenState
    extends State<NotificationDiagnosticsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _local = {};
  Map<String, dynamic> _health = {};
  Map<String, dynamic> _admin = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final local = await NotificationService.localDiagnosticsSnapshot();
      final health = await NotificationService.fetchHealthFromBackend();
      final admin = await NotificationService.fetchAdminReadiness();
      if (!mounted) return;

      setState(() {
        _local = local;
        _health = health;
        _admin = admin;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Diagnostics load failed: $error';
        _loading = false;
      });
    }
  }

  String _adminStatusText() {
    if (_admin['success'] != true) {
      return (_admin['message'] ?? 'Unavailable').toString();
    }
    return (_admin['overall_status'] ?? 'unknown').toString().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Diagnostics'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionCard(
                      context,
                      title: 'Local App State',
                      children: [
                        _row('Platform', (_local['platform'] ?? 'n/a').toString()),
                        _row('Permission', (_local['permission_granted'] == true) ? 'granted' : 'not granted'),
                        _row('Firebase Ready', (_local['firebase_ready'] == true) ? 'yes' : 'no'),
                        _row('Push Token', (_local['push_token_state'] ?? 'unknown').toString()),
                        _row('Notifications', (_local['notifications_enabled'] == true) ? 'enabled' : 'disabled'),
                        _row('Daily Reminder', (_local['daily_reminder_enabled'] == true) ? 'enabled' : 'disabled'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      context,
                      title: 'Backend User Health',
                      children: [
                        _row('Status', (_health['success'] == true) ? 'ok' : (_health['message'] ?? 'error').toString()),
                        if (_health['success'] == true) ...[
                          _row('Active Devices', '${_health['active_devices'] ?? 0}'),
                          _row('Stale Devices', '${_health['stale_devices'] ?? 0}'),
                          _row('Recent Sent', '${_health['recent_sent'] ?? 0}'),
                          _row('Recent Failed', '${_health['recent_failed'] ?? 0}'),
                          _row('FCM Configured', (_health['firebase_configured'] == true) ? 'yes' : 'no'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      context,
                      title: 'Admin Readiness',
                      children: [
                        _row('Status', _adminStatusText()),
                        if (_admin['success'] == true) ...[
                          _row('Total Devices', '${_admin['total_devices'] ?? 0}'),
                          _row('Active Devices', '${_admin['active_devices'] ?? 0}'),
                          _row('Stale Devices', '${_admin['stale_devices'] ?? 0}'),
                          _row('Recent Sent', '${_admin['recent_sent'] ?? 0}'),
                          _row('Recent Failed', '${_admin['recent_failed'] ?? 0}'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await NotificationService.showInstantLocalNotification(
                          title: 'Notification QA',
                          body: 'Local notification test succeeded.',
                        );
                        final result = await NotificationService.triggerBackendNotification(
                          eventType: 'notification_qa_test',
                          title: 'Notification QA',
                          body: 'Push delivery test from diagnostics screen.',
                          data: {'source': 'notification_diagnostics_screen'},
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              result['success'] == true
                                  ? 'QA notification triggered (sent=${result['sent'] ?? 0}, failed=${result['failed'] ?? 0}).'
                                  : 'QA trigger failed: ${result['message'] ?? 'unknown error'}',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        await _load();
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Run End-to-End Notification QA Test'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Tip: Ensure Firebase config files are included for each target platform and test on physical devices for push delivery.',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
