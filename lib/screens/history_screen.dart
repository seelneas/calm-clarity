import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Mood? _moodFilter;
  SortOption _sortBy = SortOption.newest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<JournalEntry> _filterEntries(List<JournalEntry> entries) {
    var filtered = entries;

    // Text search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) =>
        e.summary.toLowerCase().contains(q) ||
        e.transcript.toLowerCase().contains(q) ||
        e.tags.any((t) => t.toLowerCase().contains(q))
      ).toList();
    }

    // Mood filter
    if (_moodFilter != null) {
      filtered = filtered.where((e) => e.mood == _moodFilter).toList();
    }

    // Sorting
    switch (_sortBy) {
      case SortOption.newest:
        filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case SortOption.oldest:
        filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case SortOption.mood:
        filtered.sort((a, b) => _moodScore(b.mood).compareTo(_moodScore(a.mood)));
        break;
    }

    return filtered;
  }

  int _moodScore(Mood mood) {
    switch (mood) {
      case Mood.veryGood: return 5;
      case Mood.good: return 4;
      case Mood.neutral: return 3;
      case Mood.bad: return 2;
      case Mood.veryBad: return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Search',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Search Bar
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              hintText: 'Search entries, items, or tags',
                              hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
                              prefixIcon: Icon(Icons.search, color: colors.iconDefault),
                              suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close, color: colors.iconDefault, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                              style: TextStyle(color: theme.colorScheme.onSurface),
                            ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: PopupMenuButton<SortOption>(
                          icon: Icon(Icons.sort, color: colors.iconDefault),
                          onSelected: (option) => setState(() => _sortBy = option),
                          color: colors.cardBackground,
                          itemBuilder: (context) => [
                            PopupMenuItem(value: SortOption.newest, child: Text('Newest', style: TextStyle(color: colors.textHeadline))),
                            PopupMenuItem(value: SortOption.oldest, child: Text('Oldest', style: TextStyle(color: colors.textHeadline))),
                            PopupMenuItem(value: SortOption.mood, child: Text('Mood (Best First)', style: TextStyle(color: colors.textHeadline))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/voice_recording'),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(Icons.mic, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Mood Filter Chips
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildMoodChip('All', null),
                  const SizedBox(width: 8),
                  _buildMoodChip('😄 Very Good', Mood.veryGood),
                  const SizedBox(width: 8),
                  _buildMoodChip('🙂 Good', Mood.good),
                  const SizedBox(width: 8),
                  _buildMoodChip('😐 Neutral', Mood.neutral),
                  const SizedBox(width: 8),
                  _buildMoodChip('😟 Bad', Mood.bad),
                  const SizedBox(width: 8),
                  _buildMoodChip('😢 Very Bad', Mood.veryBad),
                ],
              ),
            ),
            // Results
            Expanded(
              child: Consumer<JournalProvider>(
                builder: (context, journalProvider, child) {
                  if (journalProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
                  }

                  final filtered = _filterEntries(journalProvider.entries);

                  if (journalProvider.entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off, size: 64, color: colors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text('No entries yet', style: TextStyle(color: colors.textMuted, fontSize: 16)),
                        ],
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: colors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text('No matching entries', style: TextStyle(color: colors.textMuted, fontSize: 16)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _moodFilter = null;
                              });
                            },
                            child: const Text('Clear filters', style: TextStyle(color: AppTheme.primaryColor)),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Results count
                      Text(
                        '${filtered.length} ${filtered.length == 1 ? "entry" : "entries"} found',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.textMuted, letterSpacing: 2.0),
                      ),
                      const SizedBox(height: 16),
                      ...filtered.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Dismissible(
                            key: Key(entry.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: colors.cardBackground,
                                  title: Text('Delete Entry', style: TextStyle(color: colors.textHeadline)),
                                  content: Text('Are you sure you want to delete this journal entry? This cannot be undone.', style: TextStyle(color: colors.textMuted)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (direction) {
                              journalProvider.deleteEntry(entry.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Entry deleted'),
                                  backgroundColor: Colors.redAccent,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(Icons.delete, color: colors.onPrimaryText),
                            ),
                            child: _buildEntryCard(
                              context: context,
                              entryId: entry.id,
                              title: entry.summary.isNotEmpty ? entry.summary : 'Untitled Entry',
                              date: DateFormat('MMM dd').format(entry.timestamp).toUpperCase(),
                              content: entry.transcript,
                              tag: entry.tags.isNotEmpty ? entry.tags.first : null,
                              icon: _getMoodIcon(entry.mood),
                              iconColor: _getMoodColor(entry.mood),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 32),
                      // Action items (only from filtered entries)
                      ...() {
                        final actionItems = filtered.expand((entry) => journalProvider.getActionItems(entry.id)).toList();
                        if (actionItems.isEmpty) return <Widget>[];
                        return <Widget>[
                          Text(
                            'ACTION ITEMS',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.textMuted, letterSpacing: 2.0),
                          ),
                          const SizedBox(height: 16),
                          ...actionItems.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _buildActionItem(
                              context, journalProvider, item.entryId, item.id,
                              item.description,
                              item.dueDate != null ? 'Due ${DateFormat('MMM dd').format(item.dueDate!)}' : 'No due date',
                              false,
                              completed: item.isCompleted,
                            ),
                          )),
                        ];
                      }(),
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

  Widget _buildMoodChip(String label, Mood? mood) {
    final active = _moodFilter == mood;
    final colors = Theme.of(context).extension<AppColors>()!;
    return GestureDetector(
      onTap: () => setState(() => _moodFilter = mood),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryColor : colors.chipBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: active ? Theme.of(context).colorScheme.onPrimary : colors.textBody,
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard({
    required BuildContext context,
    required String entryId,
    required String title,
    required String date,
    required String content,
    String? tag,
    required IconData icon,
    required Color iconColor,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/entry_detail', arguments: entryId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.subtleBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textHeadline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        date,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: colors.textMuted, height: 1.5),
                  ),
                  if (tag != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(BuildContext context, JournalProvider provider, String entryId, String itemId, String title, String subtitle, bool highPriority, {bool completed = false}) {
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
          GestureDetector(
            onTap: () => provider.toggleActionItem(entryId, itemId, !completed),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: completed ? AppTheme.primaryColor : Colors.transparent,
                border: Border.all(color: AppTheme.primaryColor, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: completed ? Icon(Icons.check, size: 16, color: colors.onPrimaryText) : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: colors.textHeadline,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 11, color: colors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getMoodIcon(Mood mood) {
    switch (mood) {
      case Mood.veryGood: return Icons.sentiment_very_satisfied;
      case Mood.good: return Icons.sentiment_satisfied_alt;
      case Mood.neutral: return Icons.sentiment_neutral;
      case Mood.bad: return Icons.sentiment_dissatisfied;
      case Mood.veryBad: return Icons.sentiment_very_dissatisfied;
    }
  }

  Color _getMoodColor(Mood mood) {
    switch (mood) {
      case Mood.veryGood: return AppTheme.primaryColor;
      case Mood.good: return Colors.tealAccent;
      case Mood.neutral: return Colors.blueAccent;
      case Mood.bad: return Colors.orangeAccent;
      case Mood.veryBad: return Colors.redAccent;
    }
  }
}

enum SortOption { newest, oldest, mood }
