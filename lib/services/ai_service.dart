import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'preferences_service.dart';
import '../models/journal_entry.dart';

class AIService {
  static const Duration _pollInterval = Duration(milliseconds: 700);
  static const Duration _pollTimeout = Duration(seconds: 30);

  static Future<Map<String, dynamic>> _enqueueJob(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await PreferencesService.getAuthToken();
    if (token == null || token.trim().isEmpty) {
      return {
        'success': false,
        'message': 'Sign in required for AI features.',
      };
    }

    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {
        'success': true,
        'job_id': data['job_id'],
      };
    }

    return {
      'success': false,
      'message': data['detail'] ?? 'Unable to queue AI job',
    };
  }

  static Future<Map<String, dynamic>> _pollJob(String jobId) async {
    final token = await PreferencesService.getAuthToken();
    if (token == null || token.trim().isEmpty) {
      return {
        'success': false,
        'message': 'Sign in required for AI features.',
      };
    }

    final endAt = DateTime.now().add(_pollTimeout);
    while (DateTime.now().isBefore(endAt)) {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/ai/jobs/$jobId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['detail'] ?? 'Could not fetch AI job status',
        };
      }

      final status = (data['status'] as String?) ?? 'unknown';
      if (status == 'completed' || status == 'blocked') {
        return {
          'success': true,
          'job_id': data['job_id'],
          'status': status,
          'result': data['result'] ?? <String, dynamic>{},
        };
      }
      if (status == 'failed') {
        return {
          'success': false,
          'job_id': data['job_id'],
          'message': data['error_message'] ?? 'AI job failed',
        };
      }

      await Future<void>.delayed(_pollInterval);
    }

    return {
      'success': false,
      'message': 'AI job timed out. Please retry.',
      'job_id': jobId,
    };
  }

  static Future<Map<String, dynamic>> analyzeEntry({
    required String transcript,
    required String summary,
    required Mood mood,
    required double? moodConfidence,
    required List<String> tags,
  }) async {
    try {
      final aiEnabled = await PreferencesService.isAiProcessingEnabled();
      if (!aiEnabled) {
        return {
          'success': false,
          'message': 'AI processing is disabled in Settings.',
        };
      }

      final queued = await _enqueueJob('/ai/jobs/analyze-entry', {
          'transcript': transcript,
          'summary': summary,
          'mood': mood.name,
          'mood_confidence': moodConfidence,
          'tags': tags,
      });

      if (queued['success'] != true) {
        return queued;
      }

      final polled = await _pollJob(queued['job_id'] as String);
      if (polled['success'] != true) {
        return polled;
      }

      final data = Map<String, dynamic>.from(polled['result'] ?? const {});
      return {
        'success': true,
        'job_id': polled['job_id'],
        'status': polled['status'],
        'ai_summary': data['ai_summary'] ?? '',
        'ai_action_items': List<String>.from(data['ai_action_items'] ?? const []),
        'ai_mood_explanation': data['ai_mood_explanation'] ?? '',
        'ai_followup_prompt': data['ai_followup_prompt'] ?? '',
        'safety_flag': data['safety_flag'] ?? false,
        'crisis_resources': List<String>.from(data['crisis_resources'] ?? const []),
      };
    } catch (error) {
      return {
        'success': false,
        'message': 'AI analysis unavailable: $error',
      };
    }
  }

  static Future<Map<String, dynamic>> weeklyInsights({
    required List<JournalEntry> entries,
    required List<JournalEntry> memoryPool,
    required String timeframeLabel,
  }) async {
    try {
      final aiEnabled = await PreferencesService.isAiProcessingEnabled();
      if (!aiEnabled) {
        return {
          'success': false,
          'message': 'AI processing is disabled in Settings.',
        };
      }

      final memorySnippets = _buildMemorySnippets(
        focusEntries: entries,
        memoryPool: memoryPool,
      );

      final queued = await _enqueueJob('/ai/jobs/weekly-insights', {
          'timeframe_label': timeframeLabel,
          'memory_snippets': memorySnippets,
          'entries': entries
              .map(
                (entry) => {
                  'timestamp': entry.timestamp.toIso8601String(),
                  'summary': entry.summary,
                  'mood': entry.mood.name,
                  'tags': entry.tags,
                  'ai_summary': entry.aiSummary,
                },
              )
              .toList(),
      });

      if (queued['success'] != true) {
        return queued;
      }

      final polled = await _pollJob(queued['job_id'] as String);
      if (polled['success'] != true) {
        return polled;
      }

      final data = Map<String, dynamic>.from(polled['result'] ?? const {});
      return {
        'success': true,
        'job_id': polled['job_id'],
        'status': polled['status'],
        'weekly_summary': data['weekly_summary'] ?? '',
        'key_patterns': List<String>.from(data['key_patterns'] ?? const []),
        'coaching_priorities': List<String>.from(
          data['coaching_priorities'] ?? const [],
        ),
        'next_week_prompt': data['next_week_prompt'] ?? '',
        'memory_snippets_used': List<String>.from(
          data['memory_snippets_used'] ?? const [],
        ),
        'safety_flag': data['safety_flag'] ?? false,
        'crisis_resources': List<String>.from(data['crisis_resources'] ?? const []),
      };
    } catch (error) {
      return {
        'success': false,
        'message': 'Weekly AI insights unavailable: $error',
      };
    }
  }

  static Set<String> _tokenize(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 2)
        .toSet();
    const stopwords = {
      'the', 'and', 'for', 'with', 'that', 'this', 'from', 'your', 'have', 'been', 'are', 'was', 'you',
    };
    normalized.removeWhere(stopwords.contains);
    return normalized;
  }

  static List<String> _buildMemorySnippets({
    required List<JournalEntry> focusEntries,
    required List<JournalEntry> memoryPool,
    int limit = 5,
  }) {
    if (focusEntries.isEmpty || memoryPool.isEmpty) {
      return const [];
    }

    final focusText = focusEntries
        .map((entry) => '${entry.summary} ${entry.transcript} ${entry.tags.join(' ')}')
        .join(' ');
    final focusTokens = _tokenize(focusText);

    final focusIds = focusEntries.map((entry) => entry.id).toSet();
    final scored = <MapEntry<double, String>>[];

    for (final entry in memoryPool) {
      if (focusIds.contains(entry.id)) {
        continue;
      }

      final candidate = '${entry.summary} ${entry.transcript} ${entry.tags.join(' ')}'.trim();
      if (candidate.isEmpty) {
        continue;
      }

      final candidateTokens = _tokenize(candidate);
      final overlap = focusTokens.intersection(candidateTokens).length.toDouble();
      if (overlap <= 0) {
        continue;
      }

      final snippet = candidate.length > 160 ? '${candidate.substring(0, 160).trim()}...' : candidate;
      scored.add(MapEntry(overlap, snippet));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    final snippets = <String>[];
    for (final item in scored) {
      if (!snippets.contains(item.value)) {
        snippets.add(item.value);
      }
      if (snippets.length >= limit) {
        break;
      }
    }
    return snippets;
  }

  static Future<Map<String, dynamic>> regenerateJob(String sourceJobId) async {
    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Sign in required for AI features.',
        };
      }

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/ai/jobs/$sourceJobId/regenerate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to regenerate AI job',
        };
      }

      final jobId = data['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        return {
          'success': false,
          'message': 'Regenerate failed: invalid job id',
        };
      }

      return _pollJob(jobId);
    } catch (error) {
      return {
        'success': false,
        'message': 'Regenerate failed: $error',
      };
    }
  }

  static Future<Map<String, dynamic>> regenerateWeeklyInsights(
    String sourceJobId,
  ) async {
    final regenerated = await regenerateJob(sourceJobId);
    if (regenerated['success'] != true) {
      return regenerated;
    }

    final data = Map<String, dynamic>.from(regenerated['result'] ?? const {});
    return {
      'success': true,
      'job_id': regenerated['job_id'],
      'status': regenerated['status'],
      'weekly_summary': data['weekly_summary'] ?? '',
      'key_patterns': List<String>.from(data['key_patterns'] ?? const []),
      'coaching_priorities': List<String>.from(
        data['coaching_priorities'] ?? const [],
      ),
      'next_week_prompt': data['next_week_prompt'] ?? '',
      'memory_snippets_used': List<String>.from(
        data['memory_snippets_used'] ?? const [],
      ),
      'safety_flag': data['safety_flag'] ?? false,
      'crisis_resources': List<String>.from(data['crisis_resources'] ?? const []),
    };
  }
}
