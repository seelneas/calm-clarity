import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';
import '../services/ai_service.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  String _selectedTimeframe = '30D';
  static const Color insightsPrimary = Color(0xFFEC5B13);

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  Future<Map<String, dynamic>>? _weeklyInsightsFuture;
  String _weeklyInsightsKey = '';
  String? _lastWeeklyJobId;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Filters entries to only include those within the selected timeframe.
  List<JournalEntry> _filterEntries(List<JournalEntry> allEntries) {
    final now = DateTime.now();
    final DateTime cutoff;

    switch (_selectedTimeframe) {
      case '7D':
        cutoff = now.subtract(const Duration(days: 7));
        break;
      case '30D':
        cutoff = now.subtract(const Duration(days: 30));
        break;
      case '90D':
        cutoff = now.subtract(const Duration(days: 90));
        break;
      case '1Y':
        cutoff = now.subtract(const Duration(days: 365));
        break;
      default:
        cutoff = now.subtract(const Duration(days: 30));
    }

    return allEntries.where((e) => e.timestamp.isAfter(cutoff)).toList();
  }

  /// Returns a human-readable label for the selected timeframe.
  String _timeframeLabel() {
    switch (_selectedTimeframe) {
      case '7D':
        return 'last 7 days';
      case '30D':
        return 'last 30 days';
      case '90D':
        return 'last 90 days';
      case '1Y':
        return 'last year';
      default:
        return 'last 30 days';
    }
  }

  /// Computes mood distribution from a given list of entries.
  Map<Mood, int> _getMoodDistribution(List<JournalEntry> entries) {
    final Map<Mood, int> distribution = {};
    for (var entry in entries) {
      distribution[entry.mood] = (distribution[entry.mood] ?? 0) + 1;
    }
    return distribution;
  }

  void _onTimeframeChanged(String label) {
    if (_selectedTimeframe == label) return;
    _animController.reverse().then((_) {
      setState(() {
        _selectedTimeframe = label;
      });
      _animController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Consumer<JournalProvider>(
          builder: (context, provider, _) {
            final allEntries = provider.entries;
            final entries = _filterEntries(allEntries);
            final moodDist = _getMoodDistribution(entries);
            final avgScore = _computeAverageScore(entries);
            final allTags = _collectTags(entries);
            final aiCoverage = _computeAiCoverage(entries);
            final weeklyInsightsFuture = _ensureWeeklyInsightsFuture(
              entries,
              allEntries,
            );

            return SingleChildScrollView(
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
                              color: insightsPrimary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.analytics_outlined,
                              color: insightsPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Insights',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                '${entries.length} entries in ${_timeframeLabel()}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/settings'),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.settings_outlined,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Timeframe Selector
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _buildTimeframeButton('7D'),
                        _buildTimeframeButton('30D'),
                        _buildTimeframeButton('90D'),
                        _buildTimeframeButton('1Y'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Animated content area
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mood Sentiment Score
                        _buildSectionTitle('MOOD SENTIMENT'),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              entries.isEmpty
                                  ? '—'
                                  : avgScore.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              entries.isEmpty
                                  ? 'No data in ${_timeframeLabel()}'
                                  : '${entries.length} entries analyzed',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildAICoachSignal(aiCoverage, entries.length),
                        const SizedBox(height: 24),

                        _buildWeeklyCoachSection(weeklyInsightsFuture),
                        const SizedBox(height: 24),

                        // Mood Distribution Bar Chart
                        if (entries.isNotEmpty) ...[
                          _buildMoodDistribution(moodDist, entries.length),
                          const SizedBox(height: 40),
                        ],

                        // Mood Chart Line
                        if (entries.isNotEmpty) ...[
                          _buildSectionTitle('MOOD OVER TIME'),
                          const SizedBox(height: 16),
                          _buildChartMockup(insightsPrimary, entries),
                          const SizedBox(height: 40),
                        ],

                        // Top Tags
                        if (allTags.isNotEmpty) ...[
                          Text(
                            'Top Categories',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: allTags.entries.take(6).map((e) {
                              final color = _tagColor(e.key);
                              return _buildTag(
                                '${e.key} (${e.value})',
                                _tagIcon(e.key),
                                color,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 40),
                        ],

                        // No data state for selected timeframe
                        if (entries.isEmpty && allEntries.isNotEmpty) ...[
                          _buildInsightCard(
                            'No entries found in the ${_timeframeLabel()}. Try selecting a longer timeframe to see your insights.',
                            Icons.date_range_outlined,
                            Colors.blueGrey,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Personalized Insights
                        Text(
                          'Personalized Insights',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._buildDynamicInsights(
                          entries,
                          moodDist,
                          insightsPrimary,
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Mood Distribution ──

  Widget _buildMoodDistribution(Map<Mood, int> dist, int total) {
    final moods = [
      Mood.veryGood,
      Mood.good,
      Mood.neutral,
      Mood.bad,
      Mood.veryBad,
    ];

    return Column(
      children: moods.map((mood) {
        final count = dist[mood] ?? 0;
        final fraction = total > 0 ? count / total : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  _moodLabel(mood),
                  style: TextStyle(
                    fontSize: 12,
                    color: _moodColor(mood),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: Colors.blueGrey.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(_moodColor(mood)),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 28,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Mood Over Time Chart ──

  Widget _buildChartMockup(Color color, List<JournalEntry> entries) {
    // Show more bars for longer timeframes
    final int barCount;
    switch (_selectedTimeframe) {
      case '7D':
        barCount = 7;
        break;
      case '30D':
        barCount = 10;
        break;
      case '90D':
        barCount = 14;
        break;
      case '1Y':
        barCount = 14;
        break;
      default:
        barCount = 7;
    }

    // Sort by date ascending and take the most recent `barCount` entries
    final sorted = List<JournalEntry>.from(entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final recent = sorted.length > barCount
        ? sorted.sublist(sorted.length - barCount)
        : sorted;

    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: recent.map((entry) {
          final score = _moodScore(entry.mood);
          final height = (score / 10) * 60;
          final dayLabel = '${entry.timestamp.day}/${entry.timestamp.month}';
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: _moodColor(entry.mood),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    _moodSmallIcon(entry.mood),
                    size: 12,
                    color: _moodColor(entry.mood),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dayLabel,
                    style: const TextStyle(fontSize: 8, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Dynamic Insights ──

  List<Widget> _buildDynamicInsights(
    List<JournalEntry> entries,
    Map<Mood, int> moodDist,
    Color color,
  ) {
    final timeframe = _timeframeLabel();

    if (entries.isEmpty) {
      return [
        _buildInsightCard(
          'Start recording journal entries to see personalized mood insights and patterns here.',
          Icons.auto_awesome_outlined,
          AppTheme.primaryColor,
        ),
      ];
    }

    final widgets = <Widget>[];

    // Dominant mood insight
    if (moodDist.isNotEmpty) {
      final dominant = moodDist.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      widgets.add(
        _buildInsightCard(
          'In the $timeframe, your most common mood is "${_moodLabel(dominant.key)}" appearing in ${dominant.value} of ${entries.length} entries.',
          Icons.auto_awesome_outlined,
          _moodColor(dominant.key),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    // Entry count insight
    widgets.add(
      _buildInsightCard(
        'You\'ve recorded ${entries.length} journal ${entries.length == 1 ? "entry" : "entries"} in the $timeframe. Consistency is key to building self-awareness!',
        Icons.psychology_outlined,
        color,
      ),
    );

    return widgets;
  }

  // ── Helpers ──

  Future<Map<String, dynamic>> _ensureWeeklyInsightsFuture(
    List<JournalEntry> entries,
    List<JournalEntry> allEntries,
  ) {
    final key = [
      _selectedTimeframe,
      entries.length,
      ...entries.take(20).map((e) => '${e.id}:${e.timestamp.toIso8601String()}'),
    ].join('|');

    if (_weeklyInsightsFuture == null || _weeklyInsightsKey != key) {
      _weeklyInsightsKey = key;
      _weeklyInsightsFuture = AIService.weeklyInsights(
        entries: entries,
        memoryPool: allEntries,
        timeframeLabel: _timeframeLabel(),
      );
    }
    return _weeklyInsightsFuture!;
  }

  void _regenerateWeeklyInsights() {
    final sourceJobId = _lastWeeklyJobId;
    if (sourceJobId == null || sourceJobId.isEmpty) {
      setState(() {
        _weeklyInsightsKey = '';
        _weeklyInsightsFuture = null;
      });
      return;
    }

    setState(() {
      _weeklyInsightsFuture = AIService.regenerateWeeklyInsights(sourceJobId);
    });
  }

  void _retryWeeklyInsights() {
    setState(() {
      _weeklyInsightsKey = '';
      _weeklyInsightsFuture = null;
    });
  }

  double _computeAiCoverage(List<JournalEntry> entries) {
    if (entries.isEmpty) return 0;
    final withAi = entries.where((entry) {
      final hasSummary = (entry.aiSummary ?? '').trim().isNotEmpty;
      final hasExplanation = (entry.aiMoodExplanation ?? '').trim().isNotEmpty;
      final hasPrompt = (entry.aiFollowupPrompt ?? '').trim().isNotEmpty;
      final hasActionItems = entry.aiActionItems.isNotEmpty;
      return hasSummary || hasExplanation || hasPrompt || hasActionItems;
    }).length;
    return (withAi / entries.length).clamp(0, 1);
  }

  Widget _buildAICoachSignal(double aiCoverage, int entryCount) {
    final coveragePct = (aiCoverage * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: insightsPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: insightsPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Reflection Coverage',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entryCount == 0
                      ? 'No entries yet for this timeframe.'
                      : '$coveragePct% of entries include AI reflection.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).extension<AppColors>()!.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyCoachSection(Future<Map<String, dynamic>> future) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildInsightCard(
            'Generating your weekly coaching insights...',
            Icons.auto_awesome_outlined,
            insightsPrimary,
          );
        }

        final data = snapshot.data;
        if (data == null || data['success'] != true) {
          final errorCode = (data?['error_code'] ?? '').toString();
          final message = (data?['user_message'] ?? data?['message'] ??
                  'AI weekly coaching is unavailable right now.')
              .toString();

          if (errorCode == 'ai_disabled') {
            return _buildInsightCardWithAction(
              message,
              Icons.tune,
              Colors.blueGrey,
              actionLabel: 'Open Settings',
              onAction: () => Navigator.pushNamed(context, '/settings'),
            );
          }

          if (errorCode == 'quota_reached') {
            return _buildInsightCardWithAction(
              message,
              Icons.hourglass_top,
              Colors.orangeAccent,
              actionLabel: 'Retry Later',
              onAction: _retryWeeklyInsights,
            );
          }

          return _buildInsightCardWithAction(
            message,
            Icons.error_outline,
            Colors.blueGrey,
            actionLabel: 'Retry',
            onAction: _retryWeeklyInsights,
          );
        }

        final incomingJobId = data['job_id'] as String?;
        if (incomingJobId != null && incomingJobId.isNotEmpty) {
          _lastWeeklyJobId = incomingJobId;
        }

        final weeklySummary = (data['weekly_summary'] as String? ?? '').trim();
        final keyPatterns = List<String>.from(data['key_patterns'] ?? const []);
        final priorities = List<String>.from(
          data['coaching_priorities'] ?? const [],
        );
        final nextPrompt = (data['next_week_prompt'] as String? ?? '').trim();
        final memorySnippets = List<String>.from(
          data['memory_snippets_used'] ?? const [],
        );
        final safetyFlag =
            data['safety_flag'] == true || data['is_blocked'] == true;
        final crisisResources = List<String>.from(
          data['crisis_resources'] ?? const [],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_alt_outlined, color: insightsPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'AI Weekly Coach',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _regenerateWeeklyInsights,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Regenerate'),
                  ),
                ],
              ),
              if (weeklySummary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  weeklySummary,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).extension<AppColors>()!.textBody,
                  ),
                ),
              ],
              if (safetyFlag) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Safety mode is active for this insight. Support resources are shown below.',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ],
              if (keyPatterns.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...keyPatterns.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $item',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).extension<AppColors>()!.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
              if (priorities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Priorities:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                ...priorities.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $item',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).extension<AppColors>()!.textBody,
                      ),
                    ),
                  ),
                ),
              ],
              if (nextPrompt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Prompt: $nextPrompt',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).extension<AppColors>()!.textMuted,
                  ),
                ),
              ],
              if (memorySnippets.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Memory Used',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                ...memorySnippets.take(3).map(
                  (snippet) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $snippet',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).extension<AppColors>()!.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
              if (safetyFlag && crisisResources.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Safety Resources',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                ...crisisResources.map(
                  (resource) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $resource',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).extension<AppColors>()!.textBody,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  double _computeAverageScore(List<JournalEntry> entries) {
    if (entries.isEmpty) return 0;
    final total = entries.fold<double>(0, (sum, e) => sum + _moodScore(e.mood));
    return total / entries.length;
  }

  double _moodScore(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return 10;
      case Mood.good:
        return 8;
      case Mood.neutral:
        return 6;
      case Mood.bad:
        return 4;
      case Mood.veryBad:
        return 2;
    }
  }

  Map<String, int> _collectTags(List<JournalEntry> entries) {
    final counts = <String, int>{};
    for (var entry in entries) {
      for (var tag in entry.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    // Sort by count descending
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
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

  IconData _moodSmallIcon(Mood mood) {
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

  Color _tagColor(String tag) {
    final hash = tag.hashCode;
    final colors = [
      AppTheme.primaryColor,
      const Color(0xFFEC5B13),
      Colors.tealAccent,
      Colors.blueAccent,
      Colors.pinkAccent,
      Colors.amberAccent,
    ];
    return colors[hash.abs() % colors.length];
  }

  IconData _tagIcon(String tag) {
    final lower = tag.toLowerCase();
    if (lower.contains('product') || lower.contains('work')) {
      return Icons.work_outline;
    }
    if (lower.contains('mindful') || lower.contains('routine')) {
      return Icons.self_improvement;
    }
    if (lower.contains('morning')) {
      return Icons.wb_sunny_outlined;
    }
    if (lower.contains('team') || lower.contains('brainstorm')) {
      return Icons.group_outlined;
    }
    if (lower.contains('goal') || lower.contains('reflect')) {
      return Icons.flag_outlined;
    }
    if (lower.contains('sleep') || lower.contains('rest')) {
      return Icons.bedtime_outlined;
    }
    return Icons.label_outline;
  }

  // ── Reusable Widgets ──

  Widget _buildTimeframeButton(String label) {
    final bool active = _selectedTimeframe == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTimeframeChanged(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? insightsPrimary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? insightsPrimary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: active ? insightsPrimary : Colors.blueGrey,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.blueGrey,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildTag(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCardWithAction(
    String text,
    IconData icon,
    Color color, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
