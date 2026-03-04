import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../models/journal_entry.dart';
import '../models/action_item.dart';
import '../services/database_service.dart';

class JournalProvider with ChangeNotifier {
  List<JournalEntry> _entries = [];
  final Map<String, List<ActionItem>> _actionItems = {}; // entryId -> items
  bool _isLoading = false;

  List<JournalEntry> get entries => _entries;
  bool get isLoading => _isLoading;

  JournalProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _entries = await DatabaseService.instance.getAllEntries();

    // Load action items for each entry
    for (var entry in _entries) {
      _actionItems[entry.id] = await DatabaseService.instance
          .getActionItemsForEntry(entry.id);
    }

    _isLoading = false;
    notifyListeners();
  }

  List<ActionItem> getActionItems(String entryId) {
    return _actionItems[entryId] ?? [];
  }

  Future<void> addEntry(JournalEntry entry, List<ActionItem> items) async {
    await DatabaseService.instance.insertEntry(entry);
    for (var item in items) {
      await DatabaseService.instance.insertActionItem(item);
    }

    // Refresh local state
    _entries.insert(0, entry);
    _actionItems[entry.id] = items;
    notifyListeners();
  }

  Future<void> updateEntry(JournalEntry entry) async {
    await DatabaseService.instance.updateEntry(entry);
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      _entries[index] = entry;
      notifyListeners();
    }
  }

  Future<void> deleteEntry(String id) async {
    String? audioPath;
    for (final entry in _entries) {
      if (entry.id == id) {
        audioPath = entry.audioPath;
        break;
      }
    }

    await DatabaseService.instance.deleteEntry(id);

    if (!kIsWeb && audioPath != null && audioPath.trim().isNotEmpty) {
      try {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      } catch (_) {}
    }

    _entries.removeWhere((e) => e.id == id);
    _actionItems.remove(id);
    notifyListeners();
  }

  Future<void> toggleActionItem(
    String entryId,
    String itemId,
    bool isCompleted,
  ) async {
    await DatabaseService.instance.updateActionItemStatus(itemId, isCompleted);

    final items = _actionItems[entryId];
    if (items != null) {
      final index = items.indexWhere((it) => it.id == itemId);
      if (index != -1) {
        final item = items[index];
        items[index] = ActionItem(
          id: item.id,
          entryId: item.entryId,
          description: item.description,
          isCompleted: isCompleted,
          dueDate: item.dueDate,
        );
        notifyListeners();
      }
    }
  }

  Future<void> replaceActionItems(
    String entryId,
    List<ActionItem> items,
  ) async {
    await DatabaseService.instance.replaceActionItemsForEntry(entryId, items);
    _actionItems[entryId] = items;
    notifyListeners();
  }

  // Statistics for Insights
  Map<Mood, int> getMoodDistribution() {
    final Map<Mood, int> distribution = {};
    for (var entry in _entries) {
      distribution[entry.mood] = (distribution[entry.mood] ?? 0) + 1;
    }
    return distribution;
  }

  int getStreak() {
    if (_entries.isEmpty) return 0;

    // Sort by date descending
    final sorted = List<JournalEntry>.from(_entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int streak = 0;
    DateTime currentDay = today;

    // Check if there's an entry for today. If not, check yesterday.
    bool hasEntryForDay(DateTime day) {
      return sorted.any(
        (e) =>
            e.timestamp.year == day.year &&
            e.timestamp.month == day.month &&
            e.timestamp.day == day.day,
      );
    }

    if (!hasEntryForDay(today)) {
      currentDay = today.subtract(const Duration(days: 1));
      if (!hasEntryForDay(currentDay)) return 0;
    }

    while (hasEntryForDay(currentDay)) {
      streak++;
      currentDay = currentDay.subtract(const Duration(days: 1));
    }

    return streak;
  }

  double getMoodTrend() {
    if (_entries.length < 2) return 0.0;

    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));

    double avgScore(DateTime start, DateTime end) {
      final periodEntries = _entries
          .where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end))
          .toList();

      if (periodEntries.isEmpty) return 0.0;

      final total = periodEntries.fold<double>(
        0,
        (sum, e) => sum + _moodToScore(e.mood),
      );
      return total / periodEntries.length;
    }

    final currentAvg = avgScore(sevenDaysAgo, now);
    final previousAvg = avgScore(fourteenDaysAgo, sevenDaysAgo);

    if (previousAvg == 0) return currentAvg > 0 ? 100.0 : 0.0;

    return ((currentAvg - previousAvg) / previousAvg) * 100;
  }

  double _moodToScore(Mood mood) {
    switch (mood) {
      case Mood.veryGood:
        return 5.0;
      case Mood.good:
        return 4.0;
      case Mood.neutral:
        return 3.0;
      case Mood.bad:
        return 2.0;
      case Mood.veryBad:
        return 1.0;
    }
  }
}
