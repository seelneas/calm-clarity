import 'package:flutter/material.dart';

import '../services/ai_admin_service.dart';
import '../theme.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _error;
  List<Map<String, dynamic>> _users = const [];

  Future<bool> _ensureSensitiveReauth() async {
    final passwordController = TextEditingController();
    final mfaController = TextEditingController();
    final recoveryController = TextEditingController();
    bool submitting = false;
    bool success = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Confirm Sensitive Action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Re-authenticate to continue. Use password + MFA code, or password + a recovery code.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: mfaController,
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password is required for re-auth.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          setLocalState(() => submitting = true);
                          final result = await AIAdminService.performAdminReauth(
                            password: password,
                            mfaCode: mfaController.text.trim(),
                            recoveryCode: recoveryController.text.trim(),
                          );
                          setLocalState(() => submitting = false);
                          if (!mounted) return;
                          if (result['success'] == true) {
                            success = true;
                            Navigator.pop(ctx);
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                (result['message'] ?? 'Admin re-auth failed').toString(),
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

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({String query = ''}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await AIAdminService.fetchUsers(query: query, limit: 200);
    if (!mounted) return;

    if (result['success'] == true) {
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final users = data['users'] is List
          ? List<Map<String, dynamic>>.from(
              (data['users'] as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item)),
            )
          : <Map<String, dynamic>>[];

      setState(() {
        _users = users;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _error = (result['message'] ?? 'Unable to load users').toString();
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> user) async {
    final userId = (user['id'] as num?)?.toInt();
    final email = (user['email'] ?? 'unknown').toString();
    if (userId == null) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete User'),
            content: Text(
              'Delete user $email and all related records? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm || !mounted) return;

    final reauthed = await _ensureSensitiveReauth();
    if (!reauthed || !mounted) return;

    setState(() => _isDeleting = true);
    final result = await AIAdminService.deleteUser(userId);
    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadUsers(query: _searchController.text.trim());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((result['message'] ?? 'Delete failed').toString()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> user, bool shouldActivate) async {
    final userId = (user['id'] as num?)?.toInt();
    if (userId == null) return;

    final reauthed = await _ensureSensitiveReauth();
    if (!reauthed || !mounted) return;

    setState(() => _isDeleting = true);
    final result = shouldActivate
        ? await AIAdminService.reactivateUser(userId)
        : await AIAdminService.suspendUser(userId);
    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldActivate ? 'User reactivated.' : 'User suspended.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadUsers(query: _searchController.text.trim());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((result['message'] ?? 'Action failed').toString()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showUserSessionsDialog(Map<String, dynamic> user) async {
    final userId = (user['id'] as num?)?.toInt();
    if (userId == null) return;

    bool loading = true;
    bool busy = false;
    String? error;
    List<Map<String, dynamic>> sessions = const [];
    List<Map<String, dynamic>> devices = const [];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> load() async {
              setLocalState(() {
                loading = true;
                error = null;
              });
              final result = await AIAdminService.fetchUserSessions(userId);
              if (!mounted) return;
              if (result['success'] == true) {
                final data = Map<String, dynamic>.from(result['data'] as Map);
                setLocalState(() {
                  sessions = List<Map<String, dynamic>>.from(
                    (data['sessions'] as List? ?? const []).map(
                      (item) => Map<String, dynamic>.from(item as Map),
                    ),
                  );
                  devices = List<Map<String, dynamic>>.from(
                    (data['devices'] as List? ?? const []).map(
                      (item) => Map<String, dynamic>.from(item as Map),
                    ),
                  );
                  loading = false;
                });
                return;
              }
              setLocalState(() {
                loading = false;
                error = (result['message'] ?? 'Failed to load sessions').toString();
              });
            }

            Future<void> revokeOne(int sessionId) async {
              final reauthed = await _ensureSensitiveReauth();
              if (!reauthed || !mounted) return;

              setLocalState(() => busy = true);
              final result = await AIAdminService.revokeUserSession(userId, sessionId);
              setLocalState(() => busy = false);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text((result['message'] ?? 'Failed to revoke session').toString()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              if (result['success'] == true) {
                await load();
              }
            }

            Future<void> revokeAll() async {
              final reauthed = await _ensureSensitiveReauth();
              if (!reauthed || !mounted) return;

              setLocalState(() => busy = true);
              final result = await AIAdminService.revokeAllUserSessions(userId);
              setLocalState(() => busy = false);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text((result['message'] ?? 'Failed to revoke sessions').toString()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              if (result['success'] == true) {
                await load();
              }
            }

            if (loading && sessions.isEmpty && error == null) {
              load();
            }

            return AlertDialog(
              title: Text('Sessions: ${(user['email'] ?? '').toString()}'),
              content: SizedBox(
                width: 520,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Text(error!)
                        : SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Refresh Sessions',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                ...sessions.map((session) {
                                  final sessionId = (session['session_id'] as num?)?.toInt() ?? 0;
                                  final label = (session['device_label'] ?? session['user_agent'] ?? 'Unknown device').toString();
                                  final revoked = session['revoked_at'] != null;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(label),
                                    subtitle: Text((session['client_ip'] ?? 'Unknown IP').toString()),
                                    trailing: revoked
                                        ? const Text('Revoked', style: TextStyle(fontSize: 12))
                                        : TextButton(
                                            onPressed: busy ? null : () => revokeOne(sessionId),
                                            child: const Text('Revoke'),
                                          ),
                                  );
                                }),
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                  'Registered Devices',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                ...devices.map((device) {
                                  final platform = (device['platform'] ?? 'unknown').toString();
                                  final deviceId = (device['device_id'] ?? '').toString();
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(platform.toUpperCase()),
                                    subtitle: Text(deviceId),
                                  );
                                }),
                              ],
                            ),
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: (busy || loading) ? null : revokeAll,
                  child: const Text('Revoke All'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _asInt(Map<String, dynamic> user, String key) {
    final value = user[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  bool _asBool(Map<String, dynamic> user, String key) {
    final value = user[key];
    if (value is bool) return value;
    if (value is int) return value == 1;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('User Management'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _loadUsers(query: _searchController.text.trim()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onSubmitted: (value) => _loadUsers(query: value.trim()),
              decoration: InputDecoration(
                hintText: 'Search by email or name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => _loadUsers(query: _searchController.text.trim()),
                  icon: const Icon(Icons.arrow_forward),
                ),
                filled: true,
                fillColor: colors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.subtleBorder),
                ),
              ),
            ),
          ),
          if (_isDeleting)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _users.isEmpty
                        ? const Center(child: Text('No users found'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              final email = (user['email'] ?? '').toString();
                              final name = (user['name'] ?? '').toString();
                              final isActive = _asBool(user, 'is_active');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: colors.cardBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colors.subtleBorder),
                                ),
                                child: ExpansionTile(
                                  title: Text(
                                    name.isEmpty ? email : name,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(email),
                                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _pill('AI 7d: ${_asInt(user, 'ai_requests_last_7_days')}'),
                                        _pill('AI today: ${_asInt(user, 'ai_requests_today')}'),
                                        _pill('Push devices: ${_asInt(user, 'push_devices_active')}'),
                                        _pill(isActive ? 'Status: Active' : 'Status: Suspended'),
                                        _pill(
                                          _asBool(user, 'google_calendar_connected')
                                              ? 'Google Calendar: Connected'
                                              : 'Google Calendar: Off',
                                        ),
                                        _pill(
                                          _asBool(user, 'apple_health_connected')
                                              ? 'Apple Health: Connected'
                                              : 'Apple Health: Off',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton.icon(
                                            onPressed: _isDeleting
                                                ? null
                                                : () => _toggleActive(user, !isActive),
                                            icon: Icon(
                                              isActive
                                                  ? Icons.pause_circle_outline
                                                  : Icons.play_circle_outline,
                                              color: Colors.orangeAccent,
                                            ),
                                            label: Text(
                                              isActive ? 'Suspend' : 'Reactivate',
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                              ),
                                            ),
                                          ),
                                          TextButton.icon(
                                            onPressed: _isDeleting ? null : () => _showUserSessionsDialog(user),
                                            icon: const Icon(Icons.devices_outlined),
                                            label: const Text('Sessions'),
                                          ),
                                          TextButton.icon(
                                            onPressed: _isDeleting ? null : () => _confirmDelete(user),
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            label: const Text(
                                              'Delete User',
                                              style: TextStyle(color: Colors.redAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isActive)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Suspended users cannot sign in until reactivated.',
                                            style: TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
