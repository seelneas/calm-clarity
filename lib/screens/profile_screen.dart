import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
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
  final ImagePicker _picker = ImagePicker();

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
      child: Icon(Icons.person, color: AppTheme.primaryColor, size: 48),
    );
  }

  Widget _buildProfileAvatar(ThemeData theme) {
    final photoPath = (_profilePhotoPath ?? '').trim();
    debugPrint('[ProfileAvatar] photoPath: "$photoPath"');
    if (photoPath.isEmpty) {
      debugPrint('[ProfileAvatar] photoPath is empty, showing fallback');
      return _buildAvatarFallback(theme);
    }

    if (_isDataImagePath(photoPath)) {
      debugPrint('[ProfileAvatar] Using data:image path');
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
            debugPrint('[ProfileAvatar] data:image decode error: $error');
            return _buildAvatarFallback(theme);
          },
        );
      } catch (e) {
        debugPrint('[ProfileAvatar] data:image exception: $e');
        return _buildAvatarFallback(theme);
      }
    }

    if (kIsWeb || _isRemotePhotoPath(photoPath)) {
      debugPrint('[ProfileAvatar] Loading network image: ${photoPath.length > 100 ? "${photoPath.substring(0, 100)}..." : photoPath}');
      return Image.network(
        photoPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[ProfileAvatar] Network image load FAILED: $error');
          return _buildAvatarFallback(theme);
        },
      );
    }

    debugPrint('[ProfileAvatar] Loading local file image');
    return Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[ProfileAvatar] File image load FAILED: $error');
        return _buildAvatarFallback(theme);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    // Proactively sync from backend to get latest profile photo URL
    AuthService.syncCurrentUserProfile().then((result) {
      debugPrint('[ProfileScreen] syncCurrentUserProfile result: $result');
      if (mounted) _loadPreferences();
    }).catchError((e) {
      debugPrint('[ProfileScreen] syncCurrentUserProfile error: $e');
    });
  }

  Future<void> _loadPreferences() async {
    final name = await PreferencesService.getUserName();
    final email = await PreferencesService.getUserEmail();
    final photo = await PreferencesService.getProfilePhotoPath();
    final fs = await PreferencesService.getFontSize();

    if (mounted) {
      setState(() {
        _userName = name;
        _userEmail = email;
        _profilePhotoPath = photo;
        _fontSize = fs;
        _isLoading = false;
      });

      // Proactively refresh the photo URL if it's a remote Supabase URL
      if (photo != null && _isRemotePhotoPath(photo)) {
        final refreshed = await MediaService.refreshMediaUrl(photo);
        if (refreshed != null && refreshed != photo && mounted) {
          debugPrint('[ProfileScreen] Photo URL refreshed: $refreshed');
          await PreferencesService.setProfilePhotoPath(refreshed);
          setState(() {
            _profilePhotoPath = refreshed;
          });
        }
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
                                    child: _buildProfileAvatar(theme),
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
                      ]),
                      const SizedBox(height: 32),
                      _buildSectionHeader('APPEARANCE'),
                      _buildSettingsContainer(
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, _) {
                            return Column(
                              children: [
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
      final uploadResult = await MediaService.uploadProfilePhoto(image);
      debugPrint('[ProfilePhoto] Upload result: $uploadResult');
      if (uploadResult['success'] == true &&
          (uploadResult['public_url'] ?? '').toString().trim().isNotEmpty) {
        storedPhoto = (uploadResult['public_url'] as String).trim();
        debugPrint('[ProfilePhoto] Using uploaded URL: $storedPhoto');
      } else {
        debugPrint('[ProfilePhoto] Upload failed or no public_url, using local fallback');
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
      }

      await PreferencesService.setProfilePhotoPath(storedPhoto);
      debugPrint('[ProfilePhoto] Saved photo path: $storedPhoto');
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
    if (!mounted) return;
    await Provider.of<JournalProvider>(context, listen: false).loadData();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
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
}
