import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    if (result['success'] != true && result['requires_mfa'] == true) {
      final provided = await _promptForAdminMfaCode(
        title: 'Admin MFA Required',
        message: 'Enter your 6-digit admin MFA code to access admin tools.',
      );
      if (provided == null) {
        setState(() {
          _error = 'Admin MFA challenge is required.';
          _isLoading = false;
        });
        return;
      }
      AIAdminService.setAdminTotpCode(provided);
      final retried = await AIAdminService.fetchUserSummary();
      if (!mounted) return;
      if (retried['success'] == true) {
        setState(() {
          _summary = Map<String, dynamic>.from(retried['data'] as Map);
          _isLoading = false;
          _error = null;
        });
        return;
      }
    }

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

  Future<String?> _promptForAdminMfaCode({
    required String title,
    required String message,
  }) async {
    final codeController = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'MFA code',
                  hintText: '123456',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, codeController.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _showAdminMfaManagementDialog() async {
    Map<String, dynamic>? setup;
    Map<String, dynamic>? recoveryStatus;
    String? infoMessage;

    Future<bool> requireStepUp() async {
      final passwordController = TextEditingController();
      final codeController = TextEditingController();
      final recoveryController = TextEditingController();
      bool success = false;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          bool submitting = false;
          return StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                title: const Text('Re-authenticate Admin Action'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'MFA code (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: recoveryController,
                      decoration: const InputDecoration(
                        labelText: 'Recovery code (optional)',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: submitting ? null : () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final password = passwordController.text.trim();
                            if (password.isEmpty) {
                              return;
                            }
                            setLocalState(() => submitting = true);
                            final response = await AIAdminService.performAdminReauth(
                              password: password,
                              mfaCode: codeController.text.trim(),
                              recoveryCode: recoveryController.text.trim(),
                            );
                            setLocalState(() => submitting = false);
                            if (!mounted) return;
                            if (response['success'] == true) {
                              success = true;
                              Navigator.pop(ctx);
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  (response['message'] ?? 'Admin re-auth failed').toString(),
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                    child: const Text('Continue'),
                  ),
                ],
              );
            },
          );
        },
      );

      return success;
    }

    Future<void> loadSetup() async {
      final response = await AIAdminService.fetchAdminMfaSetup();
      if (response['success'] == true) {
        setup = Map<String, dynamic>.from(response['data'] as Map);
        final recovery = await AIAdminService.fetchRecoveryCodesStatus();
        if (recovery['success'] == true) {
          recoveryStatus = Map<String, dynamic>.from(recovery['data'] as Map);
        }
        infoMessage = null;
        return;
      }

      if (response['requires_mfa'] == true) {
        final code = await _promptForAdminMfaCode(
          title: 'MFA Challenge',
          message: 'Enter your current admin MFA code to continue.',
        );
        if (code == null) {
          infoMessage = 'MFA code is required to manage admin security.';
          return;
        }
        AIAdminService.setAdminTotpCode(code);
        final retry = await AIAdminService.fetchAdminMfaSetup();
        if (retry['success'] == true) {
          setup = Map<String, dynamic>.from(retry['data'] as Map);
          final recovery = await AIAdminService.fetchRecoveryCodesStatus();
          if (recovery['success'] == true) {
            recoveryStatus = Map<String, dynamic>.from(recovery['data'] as Map);
          }
          infoMessage = null;
          return;
        }
        infoMessage = (retry['message'] ?? 'Unable to load MFA setup').toString();
        return;
      }

      infoMessage = (response['message'] ?? 'Unable to load MFA setup').toString();
    }

    await loadSetup();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool busy = false;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final enabled = setup?['mfa_enabled'] == true;
            final secret = (setup?['secret'] ?? '').toString();
            final remainingCodes = (recoveryStatus?['remaining_codes'] ?? 0).toString();
            return AlertDialog(
              title: const Text('Admin MFA Security'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (infoMessage != null) ...[
                    Text(
                      infoMessage!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(enabled ? 'Status: Enabled' : 'Status: Disabled'),
                  const SizedBox(height: 8),
                  Text('Recovery codes remaining: $remainingCodes'),
                  const SizedBox(height: 8),
                  if (secret.isNotEmpty)
                    SelectableText(
                      'Setup secret: $secret',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                        },
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final reauthed = await requireStepUp();
                          if (!reauthed || !mounted) return;
                          final code = await _promptForAdminMfaCode(
                            title: enabled ? 'Disable Admin MFA' : 'Enable Admin MFA',
                            message: enabled
                                ? 'Enter your current MFA code to disable MFA.'
                                : 'Enter a fresh MFA code from your authenticator to enable MFA.',
                          );
                          if (code == null) {
                            return;
                          }
                          setLocalState(() => busy = true);
                          final action = enabled
                              ? await AIAdminService.disableAdminMfa(code)
                              : await AIAdminService.enableAdminMfa(code);
                          if (action['requires_reauth'] == true) {
                            AIAdminService.clearAdminStepUpToken();
                          }
                          if (action['requires_mfa'] == true && action['success'] != true) {
                            final newCode = await _promptForAdminMfaCode(
                              title: 'MFA Challenge',
                              message: 'Enter your admin MFA code and try again.',
                            );
                            if (newCode != null) {
                              AIAdminService.setAdminTotpCode(newCode);
                            }
                          }
                          await loadSetup();
                          setLocalState(() => busy = false);
                          if (!mounted) return;
                          final successPayload = action['data'];
                          final actionMessage = action['success'] == true
                              ? ((successPayload is Map && successPayload['message'] != null)
                                    ? successPayload['message'].toString()
                                    : '')
                              : (action['message'] ?? '').toString();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                actionMessage.isNotEmpty
                                    ? actionMessage
                                    :
                                    (enabled ? 'MFA disabled' : 'MFA enabled'),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  child: Text(enabled ? 'Disable MFA' : 'Enable MFA'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final reauthed = await requireStepUp();
                          if (!reauthed || !mounted) return;
                          setLocalState(() => busy = true);
                          final regen = await AIAdminService.regenerateRecoveryCodes();
                          await loadSetup();
                          setLocalState(() => busy = false);
                          if (!mounted) return;
                          if (regen['success'] == true) {
                            final data = Map<String, dynamic>.from(regen['data'] as Map);
                            final codes = (data['codes'] as List?)
                                    ?.map((item) => item.toString())
                                    .toList() ??
                                <String>[];
                            if (codes.isNotEmpty) {
                              await Clipboard.setData(
                                ClipboardData(text: codes.join('\n')),
                              );
                            }
                            await showDialog<void>(
                              context: context,
                              builder: (innerCtx) {
                                return AlertDialog(
                                  title: const Text('New Recovery Codes'),
                                  content: SizedBox(
                                    width: 420,
                                    child: SingleChildScrollView(
                                      child: SelectableText(codes.join('\n')),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(innerCtx),
                                      child: const Text('Done'),
                                    ),
                                  ],
                                );
                              },
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Recovery codes copied to clipboard.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                (regen['message'] ?? 'Failed to regenerate recovery codes').toString(),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  child: const Text('Regenerate Recovery Codes'),
                ),
              ],
            );
          },
        );
      },
    );
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
            tooltip: 'Admin MFA Security',
            onPressed: _showAdminMfaManagementDialog,
            icon: const Icon(Icons.security),
          ),
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
