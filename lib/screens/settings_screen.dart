import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../services/preferences_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../services/account_access_service.dart';
import '../widgets/guest_mode_banner.dart';
import 'notification_diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _notificationsPermissionGranted = false;
  bool _dailyReminderEnabled = false;
  TimeOfDay _dailyReminderTime = const TimeOfDay(hour: 20, minute: 0);
  bool _isSyncingNotifications = false;
  String? _lastBackupDate;

  bool _isRemotePhotoPath(String path) {
    final normalized = path.trim().toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('data:image/') ||
        normalized.startsWith('blob:');
  }

  bool _isDataImagePath(String path) {
    return path.trim().toLowerCase().startsWith('data:image/');
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Container(
      color: theme.cardColor,
      child: const Icon(Icons.person, color: AppTheme.primaryColor, size: 48),
    );
  }

  Widget _buildAvatarPreview(ThemeData theme, String? rawPhotoPath) {
    final photoPath = (rawPhotoPath ?? '').trim();
    debugPrint('[SettingsAvatar] photoPath: "$photoPath"');
    if (photoPath.isEmpty) {
      debugPrint('[SettingsAvatar] photoPath is empty, showing fallback');
      return _buildAvatarFallback(theme);
    }

    if (_isDataImagePath(photoPath)) {
      debugPrint('[SettingsAvatar] Using data:image path');
      try {
        final commaIndex = photoPath.indexOf(',');
        if (commaIndex <= 0 || commaIndex >= photoPath.length - 1) {
          return _buildAvatarFallback(theme);
        }
        final encoded = photoPath.substring(commaIndex + 1);
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty) {
          return _buildAvatarFallback(theme);
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[SettingsAvatar] data:image decode error: $error');
            return _buildAvatarFallback(theme);
          },
        );
      } catch (e) {
        debugPrint('[SettingsAvatar] data:image exception: $e');
        return _buildAvatarFallback(theme);
      }
    }

    if (kIsWeb || _isRemotePhotoPath(photoPath)) {
      debugPrint('[SettingsAvatar] Loading network image: ${photoPath.length > 100 ? "${photoPath.substring(0, 100)}..." : photoPath}');
      return Image.network(
        photoPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[SettingsAvatar] Network image load FAILED: $error');
          return _buildAvatarFallback(theme);
        },
      );
    }

    debugPrint('[SettingsAvatar] Loading local file image');
    return Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[SettingsAvatar] File image load FAILED: $error');
        return _buildAvatarFallback(theme);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final notifs = await PreferencesService.isNotificationsEnabled();
    final reminderEnabled = await PreferencesService.isDailyReminderEnabled();
    final reminderHour = await PreferencesService.getDailyReminderHour();
    final reminderMinute = await PreferencesService.getDailyReminderMinute();
    final permissionGranted =
        await NotificationService.areNotificationsGranted();
    final lastBackup = await PreferencesService.getLastBackupDate();
    if (mounted) {
      setState(() {
        _notificationsEnabled = notifs;
        _dailyReminderEnabled = reminderEnabled;
        _dailyReminderTime = TimeOfDay(
          hour: reminderHour,
          minute: reminderMinute,
        );
        _notificationsPermissionGranted = permissionGranted;
        _lastBackupDate = lastBackup;
      });
    }

    await _syncNotificationSettingsFromBackend();
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (enabled) {
      final granted =
          await NotificationService.requestNotificationPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notification permission is required to enable alerts.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() => _notificationsPermissionGranted = false);
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
    await NotificationService.setNotificationsEnabled(enabled);

    final granted = await NotificationService.areNotificationsGranted();
    if (!mounted) return;
    setState(() => _notificationsPermissionGranted = granted);
  }

  Future<void> _setDailyReminderEnabled(bool enabled) async {
    if (!_notificationsEnabled) {
      await _setNotificationsEnabled(true);
      if (!_notificationsEnabled) {
        return;
      }
    }

    if (enabled) {
      await NotificationService.scheduleDailyReminder(
        hour: _dailyReminderTime.hour,
        minute: _dailyReminderTime.minute,
      );
    } else {
      await NotificationService.cancelDailyReminder();
    }

    if (!mounted) return;
    setState(() => _dailyReminderEnabled = enabled);
  }

  Future<void> _pickDailyReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyReminderTime,
    );
    if (picked == null) {
      return;
    }

    if (!mounted) return;
    setState(() => _dailyReminderTime = picked);

    await PreferencesService.setDailyReminderHour(picked.hour);
    await PreferencesService.setDailyReminderMinute(picked.minute);
    if (_dailyReminderEnabled) {
      await NotificationService.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
    } else {
      await NotificationService.syncPreferencesToBackend(
        dailyReminderHour: picked.hour,
        dailyReminderMinute: picked.minute,
      );
    }
  }

  Future<void> _syncNotificationSettingsFromBackend() async {
    final isAuthenticated = await PreferencesService.isAuthenticated();
    if (!isAuthenticated) {
      return;
    }

    if (_isSyncingNotifications) return;
    setState(() => _isSyncingNotifications = true);

    final backend = await NotificationService.fetchPreferencesFromBackend();
    if (backend['success'] == true && mounted) {
      final hour = (backend['daily_reminder_hour'] as num?)?.toInt() ?? 20;
      final minute = (backend['daily_reminder_minute'] as num?)?.toInt() ?? 0;
      setState(() {
        _notificationsEnabled = backend['notifications_enabled'] == true;
        _dailyReminderEnabled = backend['daily_reminder_enabled'] == true;
        _dailyReminderTime = TimeOfDay(hour: hour, minute: minute);
      });
      await PreferencesService.setNotificationsEnabled(_notificationsEnabled);
      await PreferencesService.setDailyReminderEnabled(_dailyReminderEnabled);
      await PreferencesService.setDailyReminderHour(hour);
      await PreferencesService.setDailyReminderMinute(minute);
    }

    if (mounted) {
      setState(() => _isSyncingNotifications = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          const GuestModeBanner(
            subtitle:
                'You are in guest mode. Create an account to back up settings and keep your data synced.',
          ),
          const SizedBox(height: 20),
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
          _buildSettingsItem(
            context: context,
            icon: Icons.devices_outlined,
            title: 'Active Sessions & Devices',
            subtitle: 'View and revoke signed-in sessions',
            onTap: () => _showSessionsDialog(context),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('PREFERENCES'),
          _buildSettingsItem(
            context: context,
            icon: Icons.notifications_none_outlined,
            title: 'Notifications',
            subtitle: _notificationsPermissionGranted
                ? 'Enabled for reminders and alerts'
                : 'Permission required to send alerts',
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (v) => _setNotificationsEnabled(v),
              activeThumbColor: AppTheme.primaryColor,
            ),
            onTap: () => _setNotificationsEnabled(!_notificationsEnabled),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.schedule,
            title: 'Daily Reminder',
            subtitle: _dailyReminderEnabled
                ? 'Scheduled at ${_dailyReminderTime.format(context)}'
                : 'Off',
            trailing: Switch(
              value: _dailyReminderEnabled,
              onChanged: _notificationsEnabled
                  ? (v) => _setDailyReminderEnabled(v)
                  : null,
              activeThumbColor: AppTheme.primaryColor,
            ),
            onTap: () => _setDailyReminderEnabled(!_dailyReminderEnabled),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.access_time,
            title: 'Reminder Time',
            subtitle: _dailyReminderTime.format(context),
            onTap: _pickDailyReminderTime,
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.notifications_active_outlined,
            title: 'Send Test Notification',
            subtitle: _isSyncingNotifications
                ? 'Syncing notification preferences...'
                : 'Send a test local and push notification now',
            onTap: () async {
              await NotificationService.showInstantLocalNotification(
                title: 'Test notification',
                body: 'Your Calm Clarity notifications are working.',
              );
              await NotificationService.triggerBackendNotification(
                eventType: 'manual_test',
                title: 'Test notification',
                body: 'Your Calm Clarity notifications are working.',
                data: {'source': 'settings_test'},
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Test notification requested.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.monitor_heart_outlined,
            title: 'Notification Diagnostics',
            subtitle: 'Firebase readiness and delivery QA checks',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationDiagnosticsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('DATA'),
          _buildSettingsItem(
            context: context,
            icon: Icons.cloud_upload_outlined,
            title: 'Backup & Sync',
            subtitle: _lastBackupDate != null
                ? 'Last backup: $_lastBackupDate'
                : 'Connect to cloud storage',
            onTap: () async {
              final allowed = await AccountAccessService.requireAccount(
                context,
                featureLabel: 'Backup & Sync',
              );
              if (!allowed) return;
              if (!context.mounted) return;
              _showBackupDialog(context);
            },
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('SUPPORT'),
          _buildSettingsItem(
            context: context,
            icon: Icons.help_outline,
            title: 'Help Center',
            onTap: () => _showInfoDialog(
              context,
              'Help Center',
              'Welcome to the Calm Clarity Help Center.\n\nHere you can find guides on how to use the journal, track your mood, and manage your action items.\n\nIf you need further assistance, please contact support@calmclarity.com.',
            ),
          ),
          _buildSettingsItem(
            context: context,
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            onTap: () => _showInfoDialog(
              context,
              'Terms & Conditions',
              'By using Calm Clarity, you agree to our terms of service.\n\nThe app is provided "as is" without any warranties. We are not responsible for any data loss, though we do our best to maintain the stability of the local database.\n\nPlease respect the community guidelines if you interact with any online features.',
            ),
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

  void _showEditProfileDialog(
    BuildContext context,
    String currentName,
    String currentEmail,
    String? currentPhotoPath,
  ) {
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Edit Profile',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
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
                          border: Border.all(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _buildAvatarPreview(theme, photoPath),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery,
                            );
                            if (image != null) {
                              String nextPhotoPath = image.path;
                              final uploadResult =
                                  await MediaService.uploadProfilePhoto(image);
                              debugPrint('[SettingsPhoto] Upload result: $uploadResult');
                              if (uploadResult['success'] == true &&
                                  (uploadResult['public_url'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) {
                                nextPhotoPath =
                                    (uploadResult['public_url'] as String)
                                        .trim();
                                debugPrint('[SettingsPhoto] Using uploaded URL: $nextPhotoPath');
                              } else {
                                debugPrint('[SettingsPhoto] Upload failed/missing URL, fallback to local');
                                if (kIsWeb) {
                                  final bytes = await image.readAsBytes();
                                  final encoded = base64Encode(bytes);
                                  final lowerName = image.name.toLowerCase();
                                  var mime = 'image/jpeg';
                                  if (lowerName.endsWith('.png')) {
                                    mime = 'image/png';
                                  } else if (lowerName.endsWith('.gif')) {
                                    mime = 'image/gif';
                                  } else if (lowerName.endsWith('.webp')) {
                                    mime = 'image/webp';
                                  }
                                  nextPhotoPath = 'data:$mime;base64,$encoded';
                                }
                              }

                              setDialogState(() {
                                photoPath = nextPhotoPath;
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
                            child: Icon(
                              Icons.camera_alt,
                              color: colors.onPrimaryText,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (photoPath != null)
                    TextButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          photoPath = null;
                        });
                      },
                      icon: const Icon(
                        Icons.person_remove_outlined,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Remove Photo',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (photoPath != null) const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final newName = nameController.text.trim();
                  final newEmail = emailController.text.trim();
                  if (newName.isNotEmpty && newEmail.isNotEmpty) {
                    await PreferencesService.setUserName(newName);
                    await PreferencesService.setUserEmail(newEmail);
                    await PreferencesService.setProfilePhotoPath(
                      photoPath ?? '',
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile updated successfully!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  'Save',
                  style: TextStyle(color: colors.onPrimaryText),
                ),
              ),
            ],
          );
        },
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  'Backup & Sync',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Keep your data safe by syncing it to your cloud accounts. This includes your journal entries, mood logs, and action items.',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.sync,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(
                        'Auto-Sync',
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        'Sync data in the background',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
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
                      leading: const Icon(
                        Icons.cloud_upload,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(
                        'Manual Backup',
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        _lastBackupDate != null
                            ? 'Last: $_lastBackupDate'
                            : 'Never backed up',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          minimumSize: const Size(60, 30),
                        ),
                        onPressed: () async {
                          // Simulate backup process
                          final now = DateTime.now();
                          final dateStr =
                              "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}";
                          await PreferencesService.setLastBackupDate(dateStr);
                          if (mounted) {
                            setState(() {
                              _lastBackupDate = dateStr;
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Backup completed successfully!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'Start',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onPrimaryText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              );
            },
          );
        },
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Privacy & Security',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.fingerprint,
                    color: AppTheme.primaryColor,
                  ),
                  title: Text(
                    'Biometric Lock',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
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
                  leading: const Icon(
                    Icons.password,
                    color: AppTheme.primaryColor,
                  ),
                  title: Text(
                    'Change Password',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colors.iconDefault,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePasswordDialog(context);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Close',
                  style: TextStyle(color: AppTheme.primaryColor),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    final confirmController = TextEditingController();
    bool submitting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Change Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nextController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
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
                        final current = currentController.text.trim();
                        final next = nextController.text.trim();
                        final confirm = confirmController.text.trim();
                        if (current.isEmpty ||
                            next.isEmpty ||
                            confirm.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fill all password fields.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (next != confirm) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('New passwords do not match.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        setLocalState(() => submitting = true);
                        final result = await AuthService.changePassword(
                          current,
                          next,
                        );
                        setLocalState(() => submitting = false);
                        if (!ctx.mounted) return;

                        if (result['success'] == true) {
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                (result['message'] ?? 'Password changed')
                                    .toString(),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          Navigator.pushNamedAndRemoveUntil(
                            this.context,
                            '/auth',
                            (route) => false,
                          );
                          return;
                        }

                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              (result['message'] ?? 'Password change failed')
                                  .toString(),
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSessionsDialog(BuildContext context) {
    bool loading = true;
    bool revoking = false;
    String? error;
    List<Map<String, dynamic>> sessions = const [];
    List<Map<String, dynamic>> devices = const [];

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> load() async {
              setLocalState(() {
                loading = true;
                error = null;
              });
              final response = await AuthService.fetchActiveSessions();
              if (!context.mounted) return;
              if (response['success'] == true) {
                final data = Map<String, dynamic>.from(response['data'] as Map);
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
                error = (response['message'] ?? 'Failed to load sessions')
                    .toString();
                loading = false;
              });
            }

            Future<void> revokeOne(int sessionId) async {
              setLocalState(() => revoking = true);
              final result = await AuthService.revokeSession(sessionId);
              setLocalState(() => revoking = false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    (result['message'] ?? 'Session revoke failed').toString(),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              if (result['success'] == true) {
                await load();
              }
            }

            Future<void> revokeAll() async {
              setLocalState(() => revoking = true);
              final result = await AuthService.revokeAllSessions();
              setLocalState(() => revoking = false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    (result['message'] ?? 'Failed to revoke all sessions')
                        .toString(),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              if (result['success'] == true) {
                Navigator.pop(ctx);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/auth',
                  (route) => false,
                );
              }
            }

            if (loading && sessions.isEmpty && error == null) {
              load();
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Active Sessions & Devices'),
              content: SizedBox(
                width: 520,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Text(error!)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Sessions',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ...sessions.map((session) {
                              final sessionId =
                                  (session['session_id'] as num?)?.toInt() ?? 0;
                              final label =
                                  (session['device_label'] ??
                                          session['user_agent'] ??
                                          'Unknown device')
                                      .toString();
                              final ip = (session['client_ip'] ?? 'Unknown IP')
                                  .toString();
                              final revokedAt = session['revoked_at'];
                              final isCurrent = session['current'] == true;
                              final isActive = revokedAt == null;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  isCurrent ? '$label (current)' : label,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text('IP: $ip'),
                                trailing: isActive
                                    ? TextButton(
                                        onPressed: revoking
                                            ? null
                                            : () => revokeOne(sessionId),
                                        child: const Text('Revoke'),
                                      )
                                    : const Text(
                                        'Revoked',
                                        style: TextStyle(fontSize: 12),
                                      ),
                              );
                            }),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'Registered Devices',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ...devices.map((device) {
                              final platform = (device['platform'] ?? 'unknown')
                                  .toString();
                              final appVersion = (device['app_version'] ?? '')
                                  .toString();
                              final deviceId = (device['device_id'] ?? '')
                                  .toString();
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(platform.toUpperCase()),
                                subtitle: Text(
                                  appVersion.isNotEmpty
                                      ? '$deviceId • v$appVersion'
                                      : deviceId,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: revoking ? null : () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: (revoking || loading) ? null : revokeAll,
                  child: const Text('Revoke All Sessions'),
                ),
              ],
            );
          },
        );
      },
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
        title: Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: TextStyle(color: colors.textMuted, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Close',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
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
          child: Icon(
            icon,
            color: titleColor ?? theme.colorScheme.onSurface,
            size: 20,
          ),
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
        trailing:
            trailing ??
            Icon(Icons.chevron_right, color: colors.iconDefault, size: 20),
      ),
    );
  }
}
