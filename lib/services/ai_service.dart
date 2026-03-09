import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'preferences_service.dart';
import '../models/journal_entry.dart';

class AIService {
  static const Duration _pollInterval = Duration(milliseconds: 700);
  static const Duration _pollTimeout = Duration(seconds: 30);

  static Map<String, dynamic> _decodeBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _standardizedError({
    required String fallbackMessage,
    String? rawMessage,
    int? statusCode,
    String? jobId,
  }) {
    final raw = (rawMessage ?? '').trim();
    final lowered = raw.toLowerCase();

    String errorCode = 'ai_unavailable';
    String userMessage = raw.isNotEmpty ? raw : fallbackMessage;
    String suggestedAction = 'retry';

    if (lowered.contains('disabled in settings')) {
      errorCode = 'ai_disabled';
      userMessage = 'AI processing is off in Settings. Enable it to continue.';
      suggestedAction = 'open_settings';
    } else if (statusCode == 401 || lowered.contains('sign in required')) {
      errorCode = 'auth_required';
      userMessage = 'Please sign in again to use AI coaching features.';
      suggestedAction = 'reauth';
    } else if (statusCode == 429 || lowered.contains('quota')) {
      errorCode = 'quota_reached';
      userMessage =
          'You reached today\'s AI limit. Your entry is saved—try AI again tomorrow.';
      suggestedAction = 'wait';
    } else if (statusCode == 503 || lowered.contains('queue unavailable')) {
      errorCode = 'queue_unavailable';
      userMessage =
          'AI service is temporarily busy. Your entry is saved—please retry shortly.';
      suggestedAction = 'retry';
    } else if (lowered.contains('timed out')) {
      errorCode = 'timeout';
      userMessage =
          'AI is taking longer than expected. Please retry in a moment.';
      suggestedAction = 'retry';
    } else if (lowered.contains('network') || lowered.contains('connection')) {
      errorCode = 'network_error';
      userMessage =
          'Network issue detected while contacting AI. Please check your connection and retry.';
      suggestedAction = 'retry';
    }

    return {
      'success': false,
      'error_code': errorCode,
      'message': userMessage,
      'user_message': userMessage,
      'suggested_action': suggestedAction,
      if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
    };
  }

  static Future<Map<String, dynamic>> _enqueueJob(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await PreferencesService.getAuthToken();
    if (token == null || token.trim().isEmpty) {
      return _standardizedError(
        fallbackMessage: 'Sign in required for AI features.',
        rawMessage: 'Sign in required for AI features.',
        statusCode: 401,
      );
    }

    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = _decodeBody(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'job_id': data['job_id'],
        };
      }

      return _standardizedError(
        fallbackMessage: 'Unable to queue AI job',
        rawMessage: (data['detail'] ?? '').toString(),
        statusCode: response.statusCode,
      );
    } catch (error) {
      return _standardizedError(
        fallbackMessage: 'Unable to queue AI job',
        rawMessage: 'Connection error: $error',
      );
    }
  }

  static Future<Map<String, dynamic>> _pollJob(String jobId) async {
    final token = await PreferencesService.getAuthToken();
    if (token == null || token.trim().isEmpty) {
      return _standardizedError(
        fallbackMessage: 'Sign in required for AI features.',
        rawMessage: 'Sign in required for AI features.',
        statusCode: 401,
        jobId: jobId,
      );
    }

    final endAt = DateTime.now().add(_pollTimeout);
    while (DateTime.now().isBefore(endAt)) {
      try {
        final response = await http.get(
          Uri.parse('${AuthService.baseUrl}/ai/jobs/$jobId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        final data = _decodeBody(response.body);
        if (response.statusCode != 200) {
          return _standardizedError(
            fallbackMessage: 'Could not fetch AI job status',
            rawMessage: (data['detail'] ?? '').toString(),
            statusCode: response.statusCode,
            jobId: jobId,
          );
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
          return _standardizedError(
            fallbackMessage: 'AI job failed',
            rawMessage: (data['error_message'] ?? '').toString(),
            jobId: (data['job_id'] ?? '').toString(),
          );
        }

        await Future<void>.delayed(_pollInterval);
      } catch (error) {
        return _standardizedError(
          fallbackMessage: 'Could not fetch AI job status',
          rawMessage: 'Connection error: $error',
          jobId: jobId,
        );
      }
    }

    return _standardizedError(
      fallbackMessage: 'AI job timed out. Please retry.',
      rawMessage: 'AI job timed out. Please retry.',
      jobId: jobId,
    );
  }

  static Future<Map<String, dynamic>> analyzeEntry({
    required String transcript,
    required String summary,
    required Mood mood,
    required double? moodConfidence,
    required List<String> tags,
  }) async {
    try {
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
        'is_blocked': (polled['status'] == 'blocked'),
        'ai_summary': data['ai_summary'] ?? '',
        'ai_action_items': List<String>.from(data['ai_action_items'] ?? const []),
        'ai_mood_explanation': data['ai_mood_explanation'] ?? '',
        'ai_followup_prompt': data['ai_followup_prompt'] ?? '',
        'safety_flag': data['safety_flag'] ?? false,
        'crisis_resources': List<String>.from(data['crisis_resources'] ?? const []),
      };
    } catch (error) {
      return _standardizedError(
        fallbackMessage: 'AI analysis unavailable.',
        rawMessage: 'AI analysis unavailable: $error',
      );
    }
  }

  static Future<Map<String, dynamic>> weeklyInsights({
    required List<JournalEntry> entries,
    required List<JournalEntry> memoryPool,
    required String timeframeLabel,
  }) async {
    try {
      final memorySnippets = _buildMemorySnippets(
        focusEntries: entries,
        memoryPool: memoryPool,
      );

      final memoryCandidates = memoryPool
          .map(
            (entry) => {
              'timestamp': entry.timestamp.toIso8601String(),
              'summary': entry.summary,
              'mood': entry.mood.name,
              'tags': entry.tags,
              'ai_summary': entry.aiSummary,
              'transcript': entry.transcript,
            },
          )
          .toList();

      final queued = await _enqueueJob('/ai/jobs/weekly-insights', {
          'timeframe_label': timeframeLabel,
          'memory_snippets': memorySnippets,
          'memory_candidates': memoryCandidates,
          'entries': entries
              .map(
                (entry) => {
                  'timestamp': entry.timestamp.toIso8601String(),
                  'summary': entry.summary,
                  'mood': entry.mood.name,
                  'tags': entry.tags,
                  'ai_summary': entry.aiSummary,
                  'transcript': entry.transcript,
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
        'is_blocked': (polled['status'] == 'blocked'),
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
      return _standardizedError(
        fallbackMessage: 'Weekly AI insights unavailable.',
        rawMessage: 'Weekly AI insights unavailable: $error',
      );
    }
  }

  static List<String> _buildMemorySnippets({
    required List<JournalEntry> focusEntries,
    required List<JournalEntry> memoryPool,
    int limit = 5,
  }) {
    if (focusEntries.isEmpty || memoryPool.isEmpty) {
      return const [];
    }

    final focusIds = focusEntries.map((entry) => entry.id).toSet();
    final snippets = <String>[];

    for (final entry in memoryPool) {
      if (focusIds.contains(entry.id)) {
        continue;
      }

      final candidate =
          '${entry.summary} ${entry.aiSummary ?? ''} ${entry.transcript} ${entry.tags.join(' ')}'
              .trim();
      if (candidate.isEmpty) {
        continue;
      }

      final snippet =
          candidate.length > 220 ? '${candidate.substring(0, 220).trim()}...' : candidate;
      if (!snippets.contains(snippet)) {
        snippets.add(snippet);
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
        return _standardizedError(
          fallbackMessage: 'Failed to regenerate AI job',
          rawMessage: (data['detail'] ?? '').toString(),
          statusCode: response.statusCode,
        );
      }

      final jobId = data['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        return _standardizedError(
          fallbackMessage: 'Regenerate failed: invalid job id',
          rawMessage: 'Regenerate failed: invalid job id',
        );
      }

      return _pollJob(jobId);
    } catch (error) {
      return _standardizedError(
        fallbackMessage: 'Regenerate failed.',
        rawMessage: 'Regenerate failed: $error',
      );
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
