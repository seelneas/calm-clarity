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
