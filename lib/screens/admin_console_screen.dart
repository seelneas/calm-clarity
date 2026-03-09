import 'package:flutter/material.dart';

import '../services/ai_admin_service.dart';
import '../theme.dart';
import 'ai_ops_dashboard_screen.dart';
import 'admin_user_management_screen.dart';
import 'observability_dashboard_screen.dart';

class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await AIAdminService.fetchUserSummary();
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _summary = Map<String, dynamic>.from(result['data'] as Map);
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _error = (result['message'] ?? 'Unable to load admin summary').toString();
      _isLoading = false;
    });
  }

  int _readInt(String key) {
    final value = _summary?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Admin Console'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSummary,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                  ),
                _summaryPanel(context, colors),
                const SizedBox(height: 16),
                _adminTile(
                  context,
                  icon: Icons.groups_outlined,
                  title: 'User Management',
                  subtitle: 'Search users, review activity and delete accounts',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminUserManagementScreen(),
                      ),
                    );
                  },
                ),
                _adminTile(
                  context,
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'AI Ops Dashboard',
                  subtitle: 'Queue depth, retries, failures, moderation and quota',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AIOpsDashboardScreen()),
                    );
                  },
                ),
                _adminTile(
                  context,
                  icon: Icons.monitor_heart_outlined,
                  title: 'System Observability',
                  subtitle: 'Traffic, latency, incidents, alerts and metrics',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ObservabilityDashboardScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _summaryPanel(BuildContext context, AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _metric('Total Users', _readInt('total_users').toString()),
          _metric('Active 7d', _readInt('users_active_last_7_days').toString()),
          _metric('AI Today', _readInt('ai_requests_today').toString()),
          _metric('AI Last 7d', _readInt('ai_requests_last_7_days').toString()),
          _metric('Google Linked', _readInt('users_with_google_calendar').toString()),
          _metric('Apple Linked', _readInt('users_with_apple_health').toString()),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _adminTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.textMuted),
        ),
        trailing: Icon(Icons.chevron_right, color: colors.iconDefault),
      ),
    );
  }
}
