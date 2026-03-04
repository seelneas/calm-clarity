import 'dart:convert';

enum Mood {
  veryBad,
  bad,
  neutral,
  good,
  veryGood;

  String toJson() => name;
  static Mood fromJson(String json) => Mood.values.byName(json);
}

class JournalEntry {
  final String id;
  final DateTime timestamp;
  final String transcript;
  final String summary;
  final Mood mood;
  final double? moodConfidence;
  final List<String> tags;
  final String? aiSummary;
  final List<String> aiActionItems;
  final String? aiMoodExplanation;
  final String? aiFollowupPrompt;
  final String? audioPath;
  final bool isSynced;

  JournalEntry({
    required this.id,
    required this.timestamp,
    required this.transcript,
    required this.summary,
    required this.mood,
    this.moodConfidence,
    required this.tags,
    this.aiSummary,
    this.aiActionItems = const [],
    this.aiMoodExplanation,
    this.aiFollowupPrompt,
    this.audioPath,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'transcript': transcript,
      'summary': summary,
      'mood': mood.toJson(),
      'moodConfidence': moodConfidence,
      'tags': jsonEncode(tags),
      'aiSummary': aiSummary,
      'aiActionItems': jsonEncode(aiActionItems),
      'aiMoodExplanation': aiMoodExplanation,
      'aiFollowupPrompt': aiFollowupPrompt,
      'audioPath': audioPath,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      id: map['id'],
      timestamp: DateTime.parse(map['timestamp']),
      transcript: map['transcript'],
      summary: map['summary'],
      mood: Mood.fromJson(map['mood']),
      moodConfidence: (map['moodConfidence'] as num?)?.toDouble(),
      tags: List<String>.from(jsonDecode(map['tags'])),
      aiSummary: map['aiSummary'],
      aiActionItems: map['aiActionItems'] != null
          ? List<String>.from(jsonDecode(map['aiActionItems']))
          : const [],
      aiMoodExplanation: map['aiMoodExplanation'],
      aiFollowupPrompt: map['aiFollowupPrompt'],
      audioPath: map['audioPath'],
      isSynced: map['isSynced'] == 1,
    );
  }
}
