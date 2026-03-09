import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';
import '../services/account_access_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/guest_mode_banner.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = 'Alex Rivers';
  String _userEmail = 'alex.rivers@calmclarity.com';
  String? _profilePhotoPath;
  double _fontSize = 16.0;
  bool _isLoading = true;
  bool _googleConnected = false;
  bool _isSyncingGoogleEvents = false;
  List<Map<String, dynamic>> _googleUpcomingEvents = const [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final name = await PreferencesService.getUserName();
    final email = await PreferencesService.getUserEmail();
    final photo = await PreferencesService.getProfilePhotoPath();
    final fs = await PreferencesService.getFontSize();
    final gc = await PreferencesService.isGoogleCalendarConnected();

    if (mounted) {
      setState(() {
        _userName = name;
        _userEmail = email;
        _profilePhotoPath = photo;
        _fontSize = fs;
        _googleConnected = gc;
        _isLoading = false;
      });

      if (gc) {
        await _refreshGoogleEvents();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  Text(
                    'Profile Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Scrollable Content
            Expanded(
              child: Consumer<JournalProvider>(
                builder: (context, provider, _) {
                  final entries = provider.entries;
                  final streak = _calculateStreak(entries);
                  final dominantMood = _getDominantMood(
                    provider.getMoodDistribution(),
                  );
                  final totalActions = entries.fold<int>(
                    0,
                    (sum, e) => sum + provider.getActionItems(e.id).length,
                  );
                  final completedActions = entries.fold<int>(
                    0,
                    (sum, e) =>
                        sum +
                        provider
                            .getActionItems(e.id)
                            .where((a) => a.isCompleted)
                            .length,
                  );

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      // Profile Header
                      const SizedBox(height: 24),
                      const GuestModeBanner(
                        subtitle:
                            'You are in guest mode. Create an account to unlock backups, integrations, and cross-device sync.',
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
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
                                    child: _profilePhotoPath != null
                                        ? (kIsWeb
                                              ? Image.network(
                                                  _profilePhotoPath!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Container(
                                                          color:
                                                              theme.cardColor,
                                                          child: Icon(
                                                            Icons.person,
                                                            color: AppTheme
                                                                .primaryColor,
                                                            size: 48,
                                                          ),
                                                        );
                                                      },
                                                )
                                              : Image.file(
                                                  File(_profilePhotoPath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Container(
                                                          color:
                                                              theme.cardColor,
                                                          child: Icon(
                                                            Icons.person,
                                                            color: AppTheme
                                                                .primaryColor,
                                                            size: 48,
                                                          ),
                                                        );
                                                      },
                                                ))
                                        : Image.network(
                                            'https://i.pravatar.cc/300',
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    color: theme.cardColor,
                                                    child: Icon(
                                                      Icons.person,
                                                      color:
                                                          AppTheme.primaryColor,
                                                      size: 48,
                                                    ),
                                                  );
                                                },
                                          ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: _pickImage,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.camera_alt,
                                        color: theme.colorScheme.onPrimary,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _userName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              _userEmail,
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Stats Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              '${entries.length}',
                              'Entries',
                              Icons.book_outlined,
                              AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              '$streak',
                              'Day Streak',
                              Icons.local_fire_department,
                              Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              dominantMood != null
                                  ? _moodEmoji(dominantMood)
                                  : '—',
                              dominantMood != null
                                  ? _moodLabel(dominantMood)
                                  : 'No data',
                              dominantMood != null
                                  ? _moodIcon(dominantMood)
                                  : Icons.sentiment_neutral,
                              dominantMood != null
                                  ? _moodColor(dominantMood)
                                  : Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              '$totalActions',
                              'Tasks',
                              Icons.checklist,
                              Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              totalActions > 0
                                  ? '${((completedActions / totalActions) * 100).round()}%'
                                  : '—',
                              'Completed',
                              Icons.check_circle_outline,
                              Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              entries.isNotEmpty
                                  ? '${entries.expand((e) => e.tags).toSet().length}'
                                  : '0',
                              'Tags Used',
                              Icons.label_outline,
                              Colors.pinkAccent,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),
                      // Account Section
                      _buildSectionHeader('ACCOUNT'),
                      _buildSettingsGroup([
                        _buildSettingsItem(
                          Icons.person_outline,
                          'Edit Profile',
                          onTap: _showEditProfileDialog,
                        ),
                        _buildSettingsItem(
                          Icons.camera_alt_outlined,
                          'Update Photo',
                          onTap: _pickImage,
                        ),
                        _buildSettingsItem(
                          Icons.person_remove_outlined,
                          'Remove Photo',
                          isDestructive: true,
                          onTap: _removeProfilePhoto,
                        ),
                        _buildSettingsItem(
                          Icons.file_download_outlined,
                          'Export Data',
                          onTap: () {
                            _exportData(provider);
                          },
                        ),
                        _buildSettingsItem(
                          Icons.delete_outline,
                          'Delete All Data',
                          isDestructive: true,
                          onTap: () {
                            _confirmDeleteAll(context, provider);
                          },
                        ),
                      ]),
                      const SizedBox(height: 32),
                      _buildSectionHeader('APPEARANCE'),
                      _buildSettingsContainer(
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, _) {
                            final isDark =
                                themeProvider.themeMode == ThemeMode.dark;
                            return Column(
                              children: [
                                _buildToggleItem(
                                  Icons.dark_mode_outlined,
                                  'Dark Mode',
                                  isDark,
                                  (v) async {
                                    await themeProvider.toggleTheme(v);
                                  },
                                ),
                                const Divider(
                                  color: Colors.blueGrey,
                                  height: 32,
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(
                                              Icons.text_fields,
                                              color: AppTheme.primaryColor,
                                              size: 20,
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              'Font Size',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${_fontSize.round()}px',
                                          style: const TextStyle(
                                            color: AppTheme.primaryColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Slider(
                                      value: _fontSize,
                                      min: 12,
                                      max: 24,
                                      activeColor: AppTheme.primaryColor,
                                      onChanged: (v) {
                                        setState(() => _fontSize = v);
                                        themeProvider.updateFontSize(v);
                                      },
                                      onChangeEnd: (v) async {
                                        await themeProvider.commitFontSize(v);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Integrations
                      _buildSectionHeader('INTEGRATIONS'),
                      _buildIntegrationCard(
                        Icons.calendar_month,
                        'Google Calendar',
                        _googleConnected
                            ? 'Connected • Tap for actions'
                            : 'Tap to connect',
                        _googleConnected,
                        onTap: _handleGoogleCalendarTap,
                      ),
                      if (_googleConnected) ...[
                        const SizedBox(height: 16),
                        _buildGoogleEventsPreviewCard(),
                      ],
                      const SizedBox(height: 32),
                      // Support
                      _buildSectionHeader('SUPPORT & ABOUT'),
                      _buildSettingsGroup([
                        _buildSettingsItem(
                          Icons.help_outline,
                          'Help Center',
                          onTap: () => _showInfoDialog(
                            context,
                            'Help Center',
                            'Welcome to the Calm Clarity Help Center.\n\nHere you can find guides on how to use the journal, track your mood, and manage your action items.\n\nIf you need further assistance, please contact support@calmclarity.com.',
                          ),
                        ),
                        _buildSettingsItem(
                          Icons.policy_outlined,
                          'Privacy Policy',
                          onTap: () => _showInfoDialog(
                            context,
                            'Privacy Policy',
                            'Your privacy is important to us.\n\nAll your journal entries, audio recordings, and action items are stored locally on your device. We do not transmit your personal data to external servers without your explicit consent.\n\nFor more details, please visit our website.',
                          ),
                        ),
                        _buildSettingsItem(
                          Icons.logout_rounded,
                          'Log Out',
                          isDestructive: true,
                          onTap: _confirmLogout,
                        ),
                      ]),
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          'Version 2.1.0\nMade with clarity • ${DateTime.now().year}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats Card ──

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Dialogs & Logic ──

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      String storedPhoto = image.path;
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
        storedPhoto = 'data:$mime;base64,$encoded';
      }

      await PreferencesService.setProfilePhotoPath(storedPhoto);
      setState(() {
        _profilePhotoPath = storedPhoto;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    await PreferencesService.setProfilePhotoPath('');
    if (!mounted) return;
    setState(() {
      _profilePhotoPath = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile photo removed.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _userName);
    final emailController = TextEditingController(text: _userEmail);

    showDialog(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Edit Profile',
            style: TextStyle(
              color: dialogTheme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: dialogTheme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: Colors.blueGrey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueGrey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                style: TextStyle(color: dialogTheme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.blueGrey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueGrey),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.blueGrey),
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
                  if (mounted) {
                    setState(() {
                      _userName = newName;
                      _userEmail = newEmail;
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
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
                'Save Changes',
                style: TextStyle(color: dialogTheme.colorScheme.onPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportData(JournalProvider provider) async {
    final entriesData = provider.entries
        .map(
          (e) => {
            'id': e.id,
            'timestamp': e.timestamp.toIso8601String(),
            'mood': e.mood.toString(),
            'summary': e.summary,
            'transcript': e.transcript,
            'tags': e.tags,
            'action_items': provider
                .getActionItems(e.id)
                .map(
                  (a) => {
                    'id': a.id,
                    'description': a.description,
                    'completed': a.isCompleted,
                  },
                )
                .toList(),
          },
        )
        .toList();

    final exportPayload = {
      'app': 'Calm Clarity',
      'version': '2.1.0',
      'export_date': DateTime.now().toIso8601String(),
      'user': _userName,
      'entries': entriesData,
    };
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(exportPayload);
    final fileName =
        'calm_clarity_export_${DateTime.now().millisecondsSinceEpoch}.json';

    try {
      final shareText =
          'Calm Clarity data export for $_userName (${entriesData.length} entries).';

      if (kIsWeb) {
        final bytes = Uint8List.fromList(utf8.encode(jsonString));
        final webFile = XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: fileName,
        );

        await Share.shareXFiles(
          [webFile],
          fileNameOverrides: [fileName],
          text: shareText,
          subject: 'Calm Clarity Export',
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsString(jsonString, flush: true);

        await Share.shareXFiles(
          [XFile(file.path)],
          fileNameOverrides: [fileName],
          text: shareText,
          subject: 'Calm Clarity Export',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export created and share sheet opened.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmDeleteAll(BuildContext context, JournalProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: AppTheme.cardColor,
          title: Text(
            'Delete All Data',
            style: TextStyle(color: dialogTheme.colorScheme.onSurface),
          ),
          content: const Text(
            'This will permanently delete all your journal entries and action items. This cannot be undone.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ids = provider.entries.map((e) => e.id).toList();
                for (var id in ids) {
                  await provider.deleteEntry(id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('All data cleared'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text(
                'Delete All',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    final theme = Theme.of(context);
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
            style: const TextStyle(color: Colors.blueGrey, height: 1.5),
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

  Future<void> _confirmLogout() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            return AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Log Out',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                'Are you sure you want to log out of Calm Clarity?',
                style: TextStyle(color: Colors.blueGrey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Log Out',
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    await AuthService.logout();
    await Provider.of<JournalProvider>(context, listen: false).loadData();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
  }

  Future<void> _handleGoogleCalendarTap() async {
    final allowed = await AccountAccessService.requireAccount(
      context,
      featureLabel: 'Google Calendar integration',
    );
    if (!allowed) return;

    if (!_googleConnected) {
      await _connectGoogleCalendar();
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync Upcoming Events'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _syncGoogleCalendar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_available),
                title: const Text('Create Focus Event'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _createGoogleFocusEvent();
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.redAccent),
                title: const Text(
                  'Disconnect',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _disconnectGoogleCalendar();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _connectGoogleCalendar() async {
    _showLoadingDialog('Connecting Google Calendar...');
    final result = await AuthService.connectGoogleCalendar();
    if (mounted) {
      Navigator.pop(context);
      if (result['success'] == true) {
        setState(() => _googleConnected = true);
        await AuthService.updateGoogleCalendarSyncSettings(
          autoSyncEnabled: true,
          syncIntervalMinutes: 5,
        );
        await AuthService.startGoogleCalendarAutoSyncIfEnabled();
        await _refreshGoogleEvents();
        _showSnack('Google Calendar connected.', success: true);
      } else {
        _showSnack(result['message'] ?? 'Google Calendar connection failed');
      }
    }
  }

  Future<void> _syncGoogleCalendar() async {
    _showLoadingDialog('Syncing upcoming events...');
    final syncResult = await AuthService.runGoogleCalendarSync();
    final result = syncResult['success'] == true
        ? {
            'success': true,
            'events': List<Map<String, dynamic>>.from(
              syncResult['events'] ?? const [],
            ),
          }
        : await _refreshGoogleEvents();
    if (mounted) {
      Navigator.pop(context);
      if (result['success'] == true) {
        final events = List<Map<String, dynamic>>.from(
          result['events'] ?? const [],
        );
        if (events.isEmpty) {
          _showSnack('No upcoming events found.', success: true);
        } else {
          final first = events.first;
          final summary = first['summary'] ?? 'Event';
          _showSnack(
            'Synced ${events.length} events. Next: $summary',
            success: true,
          );
        }
      } else {
        _showSnack(result['message'] ?? 'Event sync failed');
      }
    }
  }

  Future<void> _createGoogleFocusEvent() async {
    _showLoadingDialog('Creating focus event...');
    final start = DateTime.now().add(const Duration(minutes: 15));
    final end = start.add(const Duration(minutes: 30));
    final result = await AuthService.runGoogleCalendarSync(
      localChanges: [
        {
          'action': 'create',
          'client_event_id': 'focus-${DateTime.now().millisecondsSinceEpoch}',
          'summary': 'Calm Clarity Focus Session',
          'description':
              'A mindful check-in session generated from Calm Clarity.',
          'start_iso': start.toUtc().toIso8601String(),
          'end_iso': end.toUtc().toIso8601String(),
          'timezone': 'UTC',
        },
      ],
    );
    if (mounted) {
      Navigator.pop(context);
      if (result['success'] == true) {
        _showSnack('Focus event created in Google Calendar.', success: true);
      } else {
        _showSnack(result['message'] ?? 'Could not create event');
      }
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    _showLoadingDialog('Disconnecting Google Calendar...');
    final result = await AuthService.disconnectGoogleCalendar();
    if (mounted) {
      Navigator.pop(context);
      if (result['success'] == true) {
        await AuthService.stopGoogleCalendarAutoSyncLoop();
        setState(() {
          _googleConnected = false;
          _googleUpcomingEvents = const [];
        });
        _showSnack('Google Calendar disconnected.', success: true);
      } else {
        _showSnack(result['message'] ?? 'Disconnect failed');
      }
    }
  }

  Future<Map<String, dynamic>> _refreshGoogleEvents() async {
    if (mounted) {
      setState(() => _isSyncingGoogleEvents = true);
    }

    final result = await AuthService.runGoogleCalendarSync();

    if (mounted) {
      setState(() {
        _isSyncingGoogleEvents = false;
        if (result['success'] == true) {
          _googleUpcomingEvents = List<Map<String, dynamic>>.from(
            result['events'] ?? const [],
          );
        }
      });
    }
    return result;
  }

  Widget _buildGoogleEventsPreviewCard() {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_note,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                'Upcoming Events',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_isSyncingGoogleEvents)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_googleUpcomingEvents.isEmpty)
            Text(
              'No upcoming events synced yet.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            )
          else
            ..._googleUpcomingEvents.take(3).map((event) {
              final title = (event['summary'] as String?)?.trim();
              final start = (event['start_iso'] as String?)?.trim();
              final formattedStart = _formatEventDateTime(start);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formattedStart != null
                            ? '${title ?? 'Untitled'} • $formattedStart'
                            : (title ?? 'Untitled'),
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String? _formatEventDateTime(String? isoValue) {
    if (isoValue == null || isoValue.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(isoValue);
    if (parsed == null) {
      return isoValue;
    }

    final local = parsed.toLocal();
    return DateFormat('MMM d, h:mm a').format(local);
  }

  void _showLoadingDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? Colors.green : Colors.blueGrey,
      ),
    );
  }

  // ── Helpers ──

  int _calculateStreak(List<JournalEntry> entries) {
    if (entries.isEmpty) return 0;
    int streak = 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sorted = List<JournalEntry>.from(entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestDay = DateTime(
      sorted.first.timestamp.year,
      sorted.first.timestamp.month,
      sorted.first.timestamp.day,
    );
    if (today.difference(latestDay).inDays > 1) return 0;

    for (int i = 0; i < sorted.length - 1; i++) {
      final d1 = DateTime(
        sorted[i].timestamp.year,
        sorted[i].timestamp.month,
        sorted[i].timestamp.day,
      );
      final d2 = DateTime(
        sorted[i + 1].timestamp.year,
        sorted[i + 1].timestamp.month,
        sorted[i + 1].timestamp.day,
      );
      if (d1.difference(d2).inDays == 1) {
        streak++;
      } else if (d1.difference(d2).inDays > 1) {
        break;
      }
    }
    return streak;
  }

  Mood? _getDominantMood(Map<Mood, int> dist) {
    if (dist.isEmpty) return null;
    final entries = dist.entries.where((e) => e.value > 0);
    if (entries.isEmpty) return null;
    return entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String _moodEmoji(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return '😄';
      case Mood.good:
        return '🙂';
      case Mood.neutral:
        return '😐';
      case Mood.bad:
        return '😟';
      case Mood.veryBad:
        return '😢';
    }
  }

  String _moodLabel(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return 'Very Good';
      case Mood.good:
        return 'Good';
      case Mood.neutral:
        return 'Neutral';
      case Mood.bad:
        return 'Bad';
      case Mood.veryBad:
        return 'Very Bad';
    }
  }

  IconData _moodIcon(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return Icons.sentiment_very_satisfied;
      case Mood.good:
        return Icons.sentiment_satisfied_alt;
      case Mood.neutral:
        return Icons.sentiment_neutral;
      case Mood.bad:
        return Icons.sentiment_dissatisfied;
      case Mood.veryBad:
        return Icons.sentiment_very_dissatisfied;
    }
  }

  Color _moodColor(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return AppTheme.primaryColor;
      case Mood.good:
        return Colors.tealAccent;
      case Mood.neutral:
        return Colors.blueAccent;
      case Mood.bad:
        return Colors.orangeAccent;
      case Mood.veryBad:
        return Colors.redAccent;
    }
  }

  // ── Reusable Widgets ──

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: items),
    );
  }

  Widget _buildSettingsContainer(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _buildSettingsItem(
    IconData icon,
    String label, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.redAccent : AppTheme.primaryColor,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: isDestructive
          ? null
          : const Icon(Icons.chevron_right, color: Colors.blueGrey),
      onTap: onTap,
    );
  }

  Widget _buildToggleItem(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Switch(
          value: value,
          activeThumbColor: AppTheme.primaryColor,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildIntegrationCard(
    IconData icon,
    String label,
    String status,
    bool connected, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: connected
                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: connected ? AppTheme.primaryColor : Colors.blueGrey,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: connected ? Colors.greenAccent : Colors.blueGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
