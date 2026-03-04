import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/preferences_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _aiProcessingEnabled = false;
  String? _lastBackupDate;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final notifs = await PreferencesService.isNotificationsEnabled();
    final aiEnabled = await PreferencesService.isAiProcessingEnabled();
    final lastBackup = await PreferencesService.getLastBackupDate();
    if (mounted) {
      setState(() {
        _notificationsEnabled = notifs;
        _aiProcessingEnabled = aiEnabled;
        _lastBackupDate = lastBackup;
      });
    }
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
    await PreferencesService.setNotificationsEnabled(enabled);
  }

  Future<void> _setAiProcessingEnabled(bool enabled) async {
    if (!mounted) return;
    setState(() => _aiProcessingEnabled = enabled);
    await PreferencesService.setAiProcessingEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          _buildSectionHeader('ACCOUNT'),
          _buildSettingsItem(
            context: context,
            icon: Icons.person_outline,
            title: 'Profile Information',
            subtitle: 'Name, email, and avatar',
            onTap: () async {
              final name = await PreferencesService.getUserName();
              final email = await PreferencesService.getUserEmail();
              final photo = await PreferencesService.getProfilePhotoPath();
              if (context.mounted) {
                _showEditProfileDialog(context, name, email, photo);
              }
            },
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.lock_outline,
            title: 'Privacy & Security',
            subtitle: 'Password and biometric lock',
            onTap: () async {
              final bio = await PreferencesService.isBiometricEnabled();
              if (context.mounted) {
                _showPrivacyDialog(context, bio);
              }
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('PREFERENCES'),
          _buildSettingsItem(
            context: context,
            icon: Icons.dark_mode_outlined,
            title: 'Theme Mode',
            subtitle: isDark ? 'Dark mode active' : 'Light mode active',
            trailing: Switch(
              value: isDark,
              onChanged: (v) => themeProvider.toggleTheme(v),
              activeThumbColor: AppTheme.primaryColor,
            ),
            onTap: () => themeProvider.toggleTheme(!isDark),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.notifications_none_outlined,
            title: 'Notifications',
            subtitle: 'Daily reminders and alerts',
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (v) => _setNotificationsEnabled(v),
              activeThumbColor: AppTheme.primaryColor,
            ),
            onTap: () => _setNotificationsEnabled(!_notificationsEnabled),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.psychology_alt_outlined,
            title: 'AI Processing',
            subtitle: _aiProcessingEnabled
                ? 'Enabled: entries may be sent for AI analysis'
                : 'Disabled: keep all journal text local only',
            trailing: Switch(
              value: _aiProcessingEnabled,
              onChanged: (v) => _setAiProcessingEnabled(v),
              activeThumbColor: AppTheme.primaryColor,
            ),
            onTap: () => _setAiProcessingEnabled(!_aiProcessingEnabled),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('DATA'),
          _buildSettingsItem(
            context: context,
            icon: Icons.cloud_upload_outlined,
            title: 'Backup & Sync',
            subtitle: _lastBackupDate != null ? 'Last backup: $_lastBackupDate' : 'Connect to cloud storage',
            onTap: () => _showBackupDialog(context),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.delete_outline,
            title: 'Clear Local Data',
            titleColor: Colors.redAccent,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Go to Profile tab to delete all data'), behavior: SnackBarBehavior.floating),
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('SUPPORT'),
          _buildSettingsItem(
            context: context,
            icon: Icons.help_outline,
            title: 'Help Center',
            onTap: () => _showInfoDialog(context, 'Help Center', 'Welcome to the Calm Clarity Help Center.\n\nHere you can find guides on how to use the journal, track your mood, and manage your action items.\n\nIf you need further assistance, please contact support@calmclarity.com.'),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            onTap: () => _showInfoDialog(context, 'Terms & Conditions', 'By using Calm Clarity, you agree to our terms of service.\n\nThe app is provided "as is" without any warranties. We are not responsible for any data loss, though we do our best to maintain the stability of the local database.\n\nPlease respect the community guidelines if you interact with any online features.'),
          ),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text(
                  'Calm Clarity v1.0.0',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  'Developed with ❤️ by Antigravity',
                  style: TextStyle(color: colors.textMuted.withValues(alpha: 0.5), fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textMuted,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, String currentName, String currentEmail, String? currentPhotoPath) {
    final nameController = TextEditingController(text: currentName);
    final emailController = TextEditingController(text: currentEmail);
    String? photoPath = currentPhotoPath;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final picker = ImagePicker();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Edit Profile', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryColor, width: 2),
                        ),
                        child: ClipOval(
                          child: photoPath != null
                              ? Image.file(
                                  File(photoPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: theme.cardColor,
                                      child: const Icon(Icons.person, color: AppTheme.primaryColor, size: 48),
                                    );
                                  },
                                )
                              : Image.network(
                                  'https://i.pravatar.cc/300',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: theme.cardColor,
                                      child: const Icon(Icons.person, color: AppTheme.primaryColor, size: 48),
                                    );
                                  },
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                            if (image != null) {
                              setDialogState(() {
                                photoPath = image.path;
                              });
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.camera_alt, color: colors.onPrimaryText, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.textMuted)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.textMuted)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newName = nameController.text.trim();
                  final newEmail = emailController.text.trim();
                  if (newName.isNotEmpty && newEmail.isNotEmpty) {
                    await PreferencesService.setUserName(newName);
                    await PreferencesService.setUserEmail(newEmail);
                    if (photoPath != null) {
                      await PreferencesService.setProfilePhotoPath(photoPath!);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated successfully!'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  }
                },
                child: Text('Save', style: TextStyle(color: colors.onPrimaryText)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showBackupDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    bool isAutoSync = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return FutureBuilder<bool>(
            future: PreferencesService.isAutoSyncEnabled(),
            builder: (context, snapshot) {
              if (snapshot.hasData && !isAutoSync) {
                isAutoSync = snapshot.data!;
              }
              return AlertDialog(
                backgroundColor: theme.cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('Backup & Sync', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Keep your data safe by syncing it to your cloud accounts. This includes your journal entries, mood logs, and action items.',
                      style: TextStyle(color: colors.textMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sync, color: AppTheme.primaryColor),
                      title: Text('Auto-Sync', style: TextStyle(color: theme.colorScheme.onSurface)),
                      subtitle: Text('Sync data in the background', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                      trailing: Switch(
                        value: isAutoSync,
                        activeThumbColor: AppTheme.primaryColor,
                        onChanged: (val) async {
                          setDialogState(() => isAutoSync = val);
                          await PreferencesService.setAutoSyncEnabled(val);
                        },
                      ),
                    ),
                    Divider(color: colors.subtleBorder),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_upload, color: AppTheme.primaryColor),
                      title: Text('Manual Backup', style: TextStyle(color: theme.colorScheme.onSurface)),
                      subtitle: Text(_lastBackupDate != null ? 'Last: $_lastBackupDate' : 'Never backed up', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: const Size(60, 30),
                        ),
                        onPressed: () async {
                          // Simulate backup process
                          final now = DateTime.now();
                          final dateStr = "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}";
                          await PreferencesService.setLastBackupDate(dateStr);
                          if (mounted) {
                            setState(() {
                              _lastBackupDate = dateStr;
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Backup completed successfully!'), behavior: SnackBarBehavior.floating),
                            );
                          }
                        },
                        child: Text('Start', style: TextStyle(fontSize: 12, color: colors.onPrimaryText)),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close', style: TextStyle(color: AppTheme.primaryColor)),
                  ),
                ],
              );
            }
          );
        }
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, bool initialBiometric) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    bool isBiometric = initialBiometric;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Privacy & Security', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                  title: Text('Biometric Lock', style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Switch(
                    value: isBiometric,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      setState(() => isBiometric = val);
                      PreferencesService.setBiometricEnabled(val);
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password, color: AppTheme.primaryColor),
                  title: Text('Change Password', style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(Icons.chevron_right, color: colors.iconDefault),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password reset link sent to email.'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: AppTheme.primaryColor)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: TextStyle(color: colors.textMuted, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: titleColor ?? theme.colorScheme.onSurface, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: titleColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              )
            : null,
        trailing: trailing ?? Icon(Icons.chevron_right, color: colors.iconDefault, size: 20),
      ),
    );
  }
}
