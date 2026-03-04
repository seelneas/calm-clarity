import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.graphic_eq, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(width: 8),
                       Text(
                        'Calm Clarity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textHeadline,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/settings'),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.subtleBorder),
                          ),
                          child: Icon(Icons.settings_outlined, color: colors.iconDefault, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You have no new notifications'),
                              duration: Duration(seconds: 2),
                              backgroundColor: AppTheme.primaryColor,
                            ),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.subtleBorder),
                          ),
                          child: Icon(Icons.notifications_none, color: colors.iconDefault, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Consumer<JournalProvider>(
                builder: (context, journalProvider, child) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildMoodCard(journalProvider),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildStreakCard(journalProvider.getStreak()),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 48),
              // Mic Button
              Center(
                child: _buildMicButton(),
              ),
              const SizedBox(height: 48),
              // Action Items
              Consumer<JournalProvider>(
                builder: (context, journalProvider, child) {
                  final actionItems = journalProvider.entries
                      .expand((e) => journalProvider.getActionItems(e.id))
                      .where((item) => !item.isCompleted)
                      .take(3)
                      .toList();

                  if (actionItems.isEmpty) return const SizedBox.shrink();

                  return Column(
                    children: [
                      _buildSectionHeader(
                        'ACTION ITEMS',
                        'View All',
                        onActionTap: () => _showAllActionItems(context),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.subtleBorder),
                        ),
                        child: Column(
                          children: actionItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Column(
                              children: [
                                _buildTaskItem(journalProvider, item.entryId, item.id, item.description, item.isCompleted),
                                if (idx < actionItems.length - 1)
                                  Divider(color: colors.subtleBorder, height: 1),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
              // Recent Entries
              Consumer<JournalProvider>(
                builder: (context, journalProvider, child) {
                  final recentEntries = journalProvider.entries.take(2).toList();
                  if (recentEntries.isEmpty) return const SizedBox.shrink();

                  return Column(
                    children: [
                      _buildSectionHeader('RECENT ENTRIES', null, icon: Icons.history),
                      const SizedBox(height: 12),
                      ...recentEntries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/entry_detail', arguments: entry.id),
                            child: _buildRecentEntry(
                              title: entry.summary.isNotEmpty ? entry.summary : 'Untitled Entry',
                              time: _formatTimeAgo(entry.timestamp),
                              duration: 'Mood: ${entry.mood.toString().split('.').last}',
                              icon: _getMoodIcon(entry.mood),
                              iconColor: _getMoodColor(entry.mood),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
              const SizedBox(height: 100), // Space for bottom nav
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoodCard(JournalProvider provider) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final trend = provider.getMoodTrend();
    final isPositive = trend >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '7-DAY MOOD',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colors.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              if (provider.entries.length >= 2)
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: isPositive ? AppTheme.primaryColor : Colors.redAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${trend.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? AppTheme.primaryColor : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final day = DateTime.now().subtract(Duration(days: 6 - index));
              final dayEntries = provider.entries.where((e) =>
                e.timestamp.year == day.year &&
                e.timestamp.month == day.month &&
                e.timestamp.day == day.day).toList();
              
              double avgScore = 0;
              if (dayEntries.isNotEmpty) {
                final total = dayEntries.fold<double>(0, (sum, e) => sum + _moodToDouble(e.mood));
                avgScore = total / dayEntries.length;
              }

              // Height: max score 5 -> max height 40
              double height = avgScore > 0 ? (avgScore / 5.0) * 40.0 : 4.0;

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: height,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: avgScore > 0 ? (index == 6 ? 1.0 : 0.6) : 0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  double _moodToDouble(Mood mood) {
    switch (mood) {
      case Mood.veryGood: return 5.0;
      case Mood.good: return 4.0;
      case Mood.neutral: return 3.0;
      case Mood.bad: return 2.0;
      case Mood.veryBad: return 1.0;
    }
  }

  Widget _buildStreakCard(int streak) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        children: [
          Text(
            'STREAK',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
              const SizedBox(width: 4),
              Text(
                streak.toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colors.textHeadline,
                ),
              ),
            ],
          ),
          Text(
            'DAYS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/voice_recording'),
          child: ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 8),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 50,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(Icons.mic, color: colors.onPrimaryText, size: 64),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Tap to Speak',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.textBody,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ready to listen...',
          style: TextStyle(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String? action, {IconData? icon, VoidCallback? onActionTap}) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colors.textMuted,
                letterSpacing: 2.0,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: colors.textMuted.withValues(alpha: 0.5)),
            ],
          ],
        ),
        if (action != null)
          GestureDetector(
            onTap: onActionTap,
            child: Text(
              action,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
                letterSpacing: 1.2,
              ),
            ),
          ),
      ],
    );
  }

  void _showAllActionItems(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<JournalProvider>(
        builder: (context, provider, child) {
          final allItems = provider.entries
              .expand((e) => provider.getActionItems(e.id))
              .where((item) => !item.isCompleted)
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: colors.sheetBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PENDING ACTIONS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          letterSpacing: 2.0,
                        ),
                      ),
                      Text(
                        '${allItems.length} ITEMS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: allItems.isEmpty
                      ? Center(
                          child: Text(
                            'All caught up!',
                            style: TextStyle(color: colors.textMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          itemCount: allItems.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = allItems[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: colors.cardBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colors.subtleBorder),
                              ),
                              child: _buildTaskItem(
                                provider,
                                item.entryId,
                                item.id,
                                item.description,
                                item.isCompleted,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }



  Widget _buildTaskItem(JournalProvider provider, String entryId, String itemId, String text, bool completed) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => provider.toggleActionItem(entryId, itemId, !completed),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed ? AppTheme.primaryColor : Colors.transparent,
                border: Border.all(color: completed ? AppTheme.primaryColor : colors.textMuted.withValues(alpha: 0.5), width: 2),
              ),
              child: completed ? Icon(Icons.check, size: 16, color: colors.onPrimaryText) : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: completed ? colors.textMuted : colors.textBody,
                decoration: completed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final duration = DateTime.now().difference(dateTime);
    if (duration.inMinutes < 1) return 'Just now';
    if (duration.inMinutes < 60) return '${duration.inMinutes}m ago';
    if (duration.inHours < 24) return '${duration.inHours}h ago';
    return '${duration.inDays}d ago';
  }

  IconData _getMoodIcon(Mood mood) {
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

  Color _getMoodColor(Mood mood) {
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

  Widget _buildRecentEntry({
    required String title,
    required String time,
    required String duration,
    required IconData icon,
    required Color iconColor,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textHeadline,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(time, style: TextStyle(fontSize: 12, color: colors.textMuted)),
                    const SizedBox(width: 8),
                    Container(width: 4, height: 4, decoration: BoxDecoration(color: colors.textMuted, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(duration, style: TextStyle(fontSize: 12, color: colors.textMuted, fontStyle: FontStyle.italic)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textMuted),
        ],
      ),
    );
  }
}
