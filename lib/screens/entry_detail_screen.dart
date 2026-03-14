import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';
import '../models/action_item.dart';
import '../services/media_service.dart';

class EntryDetailScreen extends StatefulWidget {
  final String entryId;
  const EntryDetailScreen({super.key, required this.entryId});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  int _selectedTabIndex = 0;
  final _tabLabels = const ['Summary', 'Transcript', 'Action Items', 'Tags'];

  bool _isEditing = false;
  late TextEditingController _summaryController;
  late TextEditingController _transcriptController;
  late AudioPlayer _audioPlayer;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController();
    _transcriptController = TextEditingController();
    _audioPlayer = AudioPlayer();
    _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _audioDuration = duration);
    });
    _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _audioPosition = position);
    });
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playerState = state);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _audioPosition = Duration.zero;
        _playerState = PlayerState.completed;
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _summaryController.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  void _enterEditMode(JournalEntry entry) {
    setState(() {
      _isEditing = true;
      _summaryController.text = entry.summary;
      _transcriptController.text = entry.transcript;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
    });
  }

  Future<void> _saveEdit(JournalProvider provider, JournalEntry entry) async {
    final updatedEntry = JournalEntry(
      id: entry.id,
      timestamp: entry.timestamp,
      transcript: _transcriptController.text,
      summary: _summaryController.text,
      mood: entry.mood,
      moodConfidence: entry.moodConfidence,
      tags: entry.tags,
      aiSummary: entry.aiSummary,
      aiActionItems: entry.aiActionItems,
      aiMoodExplanation: entry.aiMoodExplanation,
      aiFollowupPrompt: entry.aiFollowupPrompt,
      audioPath: entry.audioPath,
      isSynced: entry.isSynced,
    );

    await provider.updateEntry(updatedEntry);
    setState(() {
      _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry updated successfully'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JournalProvider>(
      builder: (context, provider, _) {
        final entry = provider.entries.firstWhere(
          (e) => e.id == widget.entryId,
          orElse: () => JournalEntry(
            id: '',
            timestamp: DateTime.now(),
            transcript: '',
            summary: 'Entry not found',
            mood: Mood.neutral,
            tags: [],
          ),
        );

        if (entry.id.isEmpty) {
          final colors = Theme.of(context).extension<AppColors>()!;
          return Scaffold(
            body: Center(
              child: Text(
                'Entry not found',
                style: TextStyle(color: colors.textHeadline),
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final colors = theme.extension<AppColors>()!;
        final actionItems = provider.getActionItems(widget.entryId);
        final formattedDate = DateFormat(
          'MMMM d, yyyy',
        ).format(entry.timestamp);

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _isEditing
                                  ? 'Editing Entry'
                                  : (entry.summary.isNotEmpty
                                        ? entry.summary
                                        : 'Untitled Entry'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isEditing) ...[
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            color: colors.iconDefault,
                          ),
                          onPressed: () => _enterEditMode(entry),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () =>
                              _confirmDelete(context, provider, entry.id),
                        ),
                      ] else ...[
                        TextButton(
                          onPressed: _cancelEdit,
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: colors.textMuted),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _saveEdit(provider, entry),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(color: theme.dividerColor),
                // Scrollable Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Mood Badge
                      _buildMoodBadge(entry.mood, entry.moodConfidence),
                      const SizedBox(height: 16),
                      _buildAIReflectionCard(entry),
                      const SizedBox(height: 24),
                      // Audio Player (visual placeholder)
                      _buildAudioPlayer(entry),
                      const SizedBox(height: 32),
                      // Tabs
                      _buildTabs(),
                      const SizedBox(height: 24),
                      // Tab Content
                      _buildTabContent(entry, actionItems, provider),
                      const SizedBox(height: 32),
                      // Related Entries
                      if (!_isEditing) _buildRelatedEntries(provider, entry.id),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoodBadge(Mood mood, double? confidence) {
    final label = _moodLabel(mood);
    final icon = _moodIcon(mood);
    final color = _moodColor(mood);
    final confidencePct = confidence == null
        ? null
        : (confidence * 100).clamp(0, 100).toStringAsFixed(0);

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (confidencePct != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              'Confidence $confidencePct%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).extension<AppColors>()!.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAIReflectionCard(JournalEntry entry) {
    final hasAiSummary = (entry.aiSummary ?? '').trim().isNotEmpty;
    final hasAiMoodExplanation =
        (entry.aiMoodExplanation ?? '').trim().isNotEmpty;
    final hasAiPrompt = (entry.aiFollowupPrompt ?? '').trim().isNotEmpty;
    final hasAiItems = entry.aiActionItems.isNotEmpty;
    final hasAnyAi =
        hasAiSummary || hasAiMoodExplanation || hasAiPrompt || hasAiItems;

    if (!hasAnyAi) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppTheme.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Reflection',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          if (hasAiSummary) ...[
            const SizedBox(height: 10),
            Text(
              entry.aiSummary!.trim(),
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ],
          if (hasAiMoodExplanation) ...[
            const SizedBox(height: 10),
            Text(
              entry.aiMoodExplanation!.trim(),
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],
          if (hasAiItems) ...[
            const SizedBox(height: 12),
            ...entry.aiActionItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(fontSize: 13, color: colors.textBody),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (hasAiPrompt) ...[
            const SizedBox(height: 10),
            Text(
              'Follow-up: ${entry.aiFollowupPrompt!.trim()}',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioPlayer(JournalEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final hasAudio = (entry.audioPath ?? '').trim().isNotEmpty;
    final effectiveDuration = _audioDuration.inMilliseconds > 0
        ? _audioDuration
        : Duration(seconds: 1);
    final progress =
        (_audioPosition.inMilliseconds / effectiveDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final isPlaying = _playerState == PlayerState.playing;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          if (!hasAudio)
            Text(
              'No audio recording saved for this entry.',
              style: TextStyle(color: colors.textMuted),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(24, (index) {
                double height = (index % 5 + 3) * 4.0;
                return Container(
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(
                    color: index < (progress * 24).floor()
                        ? AppTheme.primaryColor
                        : theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              GestureDetector(
                onTap: hasAudio ? () => _togglePlayback(entry) : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasAudio ? AppTheme.primaryColor : colors.textMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: hasAudio ? progress : 0,
                      backgroundColor: colors.textMuted.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation(
                        AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: hasAudio ? progress : 0,
                        onChanged: hasAudio
                            ? (value) => _seekPlayback(value)
                            : null,
                        activeColor: AppTheme.primaryColor,
                        inactiveColor: colors.textMuted.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_audioPosition),
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                        ),
                        Text(
                          hasAudio ? _formatDuration(_audioDuration) : '--:--',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasAudio) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed:
                      _playerState == PlayerState.stopped &&
                          _audioPosition == Duration.zero
                      ? null
                      : _stopPlayback,
                  icon: Icon(Icons.stop, color: colors.iconDefault),
                  tooltip: 'Stop',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayback(JournalEntry entry) async {
    final audioPath = entry.audioPath;
    if (audioPath == null || audioPath.trim().isEmpty) return;
    String finalPath = audioPath.trim();

    try {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer.pause();
        return;
      }

      if (_playerState == PlayerState.paused) {
        await _audioPlayer.resume();
        return;
      }

      if (finalPath.startsWith('http://') || finalPath.startsWith('https://')) {
        debugPrint('[AudioPlayer] Refreshing remote URL...');
        final refreshed = await MediaService.refreshMediaUrl(finalPath);
        if (refreshed != null && refreshed.isNotEmpty) {
          finalPath = refreshed;
        }
      }

      if (finalPath.startsWith('blob:') ||
          finalPath.startsWith('http://') ||
          finalPath.startsWith('https://')) {
        debugPrint('[AudioPlayer] Playing URL source: ${finalPath.length > 100 ? "${finalPath.substring(0, 100)}..." : finalPath}');
        await _audioPlayer.play(UrlSource(finalPath));
        return;
      }

      debugPrint('[AudioPlayer] Playing device file: $finalPath');
      await _audioPlayer.play(DeviceFileSource(finalPath));
    } catch (e) {
      debugPrint('[AudioPlayer] Playback error: $e');
      _showMessage('Unable to play this audio recording.');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _audioPosition = Duration.zero;
        _playerState = PlayerState.stopped;
      });
    } catch (_) {
      _showMessage('Unable to stop playback right now.');
    }
  }

  Future<void> _seekPlayback(double progress) async {
    if (_audioDuration.inMilliseconds <= 0) return;
    final clamped = progress.clamp(0.0, 1.0);
    final targetMs = (_audioDuration.inMilliseconds * clamped).round();

    try {
      await _audioPlayer.seek(Duration(milliseconds: targetMs));
      if (!mounted) return;
      setState(() {
        _audioPosition = Duration(milliseconds: targetMs);
      });
    } catch (_) {
      _showMessage('Unable to seek in this recording.');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildTabs() {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Row(
      children: List.generate(_tabLabels.length, (index) {
        final active = _selectedTabIndex == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppTheme.primaryColor : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _tabLabels[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: active ? AppTheme.primaryColor : colors.textMuted,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTabContent(
    JournalEntry entry,
    List<ActionItem> actionItems,
    JournalProvider provider,
  ) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    switch (_selectedTabIndex) {
      case 0: // Summary
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('AI SUMMARY'),
                if (!_isEditing)
                  IconButton(
                    icon: Icon(Icons.copy, size: 16, color: colors.iconDefault),
                    onPressed: () => _copyToClipboard(entry.summary, 'Summary'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _isEditing
                ? TextField(
                    controller: _summaryController,
                    maxLines: null,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      hintText: 'Enter summary...',
                      hintStyle: TextStyle(color: colors.textMuted),
                    ),
                  )
                : _buildSummaryCard(entry.summary),
          ],
        );
      case 1: // Transcript
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('FULL TRANSCRIPT'),
                if (!_isEditing)
                  IconButton(
                    icon: Icon(Icons.copy, size: 16, color: colors.iconDefault),
                    onPressed: () =>
                        _copyToClipboard(entry.transcript, 'Transcript'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _isEditing
                ? TextField(
                    controller: _transcriptController,
                    maxLines: null,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.8,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      hintText: 'Enter transcript...',
                      hintStyle: TextStyle(color: colors.textMuted),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text(
                      entry.transcript,
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.8,
                      ),
                    ),
                  ),
          ],
        );
      case 2: // Action Items
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('EXTRACTED ACTION ITEMS'),
            const SizedBox(height: 12),
            if (actionItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'No action items for this entry.',
                  style: TextStyle(color: colors.textMuted),
                ),
              )
            else
              ...actionItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildActionItem(provider, item),
                ),
              ),
          ],
        );
      case 3: // Tags
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('TAGS'),
            const SizedBox(height: 12),
            if (entry.tags.isEmpty)
              Text('No tags.', style: TextStyle(color: colors.textMuted))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSectionHeader(String title) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: colors.textMuted,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildSummaryCard(String summary) {
    final sentences = summary
        .split('. ')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: sentences.isEmpty
            ? [
                Text(
                  'No summary available.',
                  style: TextStyle(color: colors.textMuted),
                ),
              ]
            : sentences
                  .map(
                    (sentence) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${sentence.trim()}${sentence.endsWith('.') ? '' : '.'}',
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textBody,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  Widget _buildActionItem(JournalProvider provider, ActionItem item) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return GestureDetector(
      onTap: () =>
          provider.toggleActionItem(item.entryId, item.id, !item.isCompleted),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: item.isCompleted
              ? AppTheme.primaryColor.withValues(alpha: 0.08)
              : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isCompleted
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : theme.dividerColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: item.isCompleted
                    ? AppTheme.primaryColor
                    : Colors.transparent,
                border: Border.all(color: AppTheme.primaryColor, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: item.isCompleted
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.description,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: item.isCompleted
                      ? colors.textMuted
                      : theme.colorScheme.onSurface,
                  decoration: item.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedEntries(JournalProvider provider, String currentId) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final related = provider.entries
        .where((e) => e.id != currentId)
        .take(3)
        .toList();
    if (related.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('RELATED ENTRIES'),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: related.map((e) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntryDetailScreen(entryId: e.id),
                    ),
                  ),
                  child: Container(
                    width: 180,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _moodIcon(e.mood),
                          color: _moodColor(e.mood),
                          size: 20,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          e.summary.isNotEmpty ? e.summary : 'Untitled',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(e.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(
    BuildContext context,
    JournalProvider provider,
    String entryId,
  ) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(
          'Delete Entry',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to delete this journal entry? This cannot be undone.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteEntry(entryId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mood helpers ──

  String _moodLabel(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return 'Very Positive';
      case Mood.good:
        return 'Positive';
      case Mood.neutral:
        return 'Neutral';
      case Mood.bad:
        return 'Negative';
      case Mood.veryBad:
        return 'Very Negative';
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
}
