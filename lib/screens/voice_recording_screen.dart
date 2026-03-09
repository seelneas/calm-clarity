import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:math' as math;
import '../theme.dart';
import '../providers/journal_provider.dart';
import '../models/journal_entry.dart';
import '../models/action_item.dart';
import '../services/ai_service.dart';
import '../services/account_access_service.dart';
import '../services/notification_service.dart';

class _MoodDecision {
  final Mood mood;
  final double confidence;
  final bool usedEnergySignal;

  const _MoodDecision({
    required this.mood,
    required this.confidence,
    required this.usedEnergySignal,
  });
}

class VoiceRecordingScreen extends StatefulWidget {
  const VoiceRecordingScreen({super.key});

  @override
  State<VoiceRecordingScreen> createState() => _VoiceRecordingScreenState();
}

class _VoiceRecordingScreenState extends State<VoiceRecordingScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final SpeechToText _speechToText = SpeechToText();

  late AnimationController _waveController;
  Timer? _timer;
  int _seconds = 0;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSaving = false;
  bool _speechAvailable = false;
  String _liveTranscript = '';
  String? _audioFilePath;
  String _statusLabel = 'Initializing...';
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final List<double> _energySamples = [];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    unawaited(_initializeRecording());
  }

  Future<void> _initializeRecording() async {
    try {
      final granted = await _requestPermissions();
      if (!mounted) return;

      if (!granted) {
        setState(() {
          _statusLabel = 'Microphone permission required';
        });
        _showMessage('Please grant microphone permission to record.');
        return;
      }

      await _startRecordingSession();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Unable to start recording';
      });
      _showMessage('Could not initialize recording. Please try again.');
    }
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return true;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await Permission.speech.request();
    }

    return true;
  }

  Future<void> _startRecordingSession() async {
    try {
      final hasRecordPermission = await _audioRecorder.hasPermission();
      if (!hasRecordPermission) {
        if (!mounted) return;
        setState(() {
          _statusLabel = 'Microphone access denied';
        });
        _showMessage('Microphone access denied.');
        return;
      }

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      if (kIsWeb) {
        _audioFilePath = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(config, path: _audioFilePath!);
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        _audioFilePath = p.join(
          docsDir.path,
          'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        await _audioRecorder.start(config, path: _audioFilePath!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Failed to access recorder';
      });
      _showMessage('Failed to start recorder.');
      return;
    }

    _speechAvailable = await _speechToText.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          if (status == 'done' && _isRecording) {
            _statusLabel = 'Listening...';
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _statusLabel = 'Recording, transcription unavailable';
        });
      },
    );

    if (_speechAvailable) {
      try {
        await _speechToText.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _liveTranscript = result.recognizedWords.trim();
            });
          },
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.dictation,
            cancelOnError: false,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _statusLabel = 'Recording audio (transcription unavailable)';
        });
      }
    }

    _startEnergySampling();

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _statusLabel = _speechAvailable ? 'Listening...' : 'Recording audio...';
    });

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _audioRecorder.dispose();
    _speechToText.stop();
    _waveController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Status Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Icon(
                        Icons.close,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        size: 20,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isRecording ? Colors.red : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isRecording
                                ? (_isPaused ? 'PAUSED' : 'RECORDING')
                                : 'READY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: colors.textMuted,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(_seconds),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(11, (index) {
                        double height = 20 + (10 * (index % 5 + 1)).toDouble();
                        if (index == 5) height = 80;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 6,
                          height: height * (0.8 + 0.4 * _waveController.value),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 1 - (index - 5).abs() * 0.15,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Column(
                    children: [
                      Text(
                        _statusLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: colors.textMuted.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(minHeight: 72),
                        child: Text(
                          _liveTranscript.isEmpty
                              ? 'Speak naturally. Your words will appear here in real time.'
                              : _liveTranscript,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _liveTranscript.isEmpty ? 18 : 22,
                            color: _liveTranscript.isEmpty
                                ? colors.textMuted.withValues(alpha: 0.8)
                                : colors.textHeadline,
                            fontWeight: _liveTranscript.isEmpty
                                ? FontWeight.w500
                                : FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPauseResumeControl(),
                      _buildMainStopButton(),
                      _buildSecondaryControl(Icons.label_outline, 'TAG'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isPaused
                        ? 'Tap Resume to continue recording, or Stop to save.'
                        : 'Tap the red button to finish and save your journal entry',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryControl(IconData icon, String label) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.chipBackground,
            shape: BoxShape.circle,
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: colors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPauseResumeControl() {
    final colors = Theme.of(context).extension<AppColors>()!;
    final paused = _isPaused;
    return Column(
      children: [
        GestureDetector(
          onTap: _isSaving || !_isRecording ? null : _togglePauseResume,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.chipBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.textMuted.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          paused ? 'RESUME' : 'PAUSE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: colors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildMainStopButton() {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(Icons.stop, color: colors.onPrimaryText, size: 36),
            onPressed: _isSaving || !_isRecording
                ? null
                : () => _stopAndSave(context),
          ),
        ),
      ],
    );
  }

  Future<void> _stopAndSave(BuildContext context) async {
    if (_isSaving || !_isRecording) return;

    setState(() {
      _isSaving = true;
      _statusLabel = 'Finalizing your entry...';
    });

    _timer?.cancel();
    _waveController.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
    } catch (_) {}

    String? recordedPath;
    try {
      recordedPath = await _audioRecorder.stop();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not finalize audio file.');
      }
    }
    final now = DateTime.now();
    final formattedTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final transcript = _liveTranscript.trim().isEmpty
        ? 'Voice note recorded at $formattedTime.'
        : _liveTranscript.trim();
    final entryId = DateTime.now().millisecondsSinceEpoch.toString();

    final summary = _buildSummary(transcript);
    final tags = _buildTags(transcript);
    final moodDecision = _inferMoodDecision(transcript);
    final items = _buildActionItems(entryId, transcript);

    final entry = JournalEntry(
      id: entryId,
      timestamp: DateTime.now(),
      transcript: transcript,
      summary: summary,
      mood: moodDecision.mood,
      moodConfidence: moodDecision.confidence,
      tags: tags,
      aiSummary: null,
      aiActionItems: const [],
      aiMoodExplanation: null,
      aiFollowupPrompt: null,
      audioPath: recordedPath ?? _audioFilePath,
    );

    if (context.mounted) {
      final journalProvider = Provider.of<JournalProvider>(
        context,
        listen: false,
      );
      await journalProvider.addEntry(entry, items);
        await NotificationService.notifyEntrySaved();
      final confidencePct = (moodDecision.confidence * 100)
          .clamp(0, 100)
          .toStringAsFixed(0);
      _showMessage(
        'Voice entry saved. Mood: ${_moodLabel(moodDecision.mood)} ($confidencePct% confidence). Generating AI reflection...',
      );

      final aiResult = await AIService.analyzeEntry(
        transcript: transcript,
        summary: summary,
        mood: moodDecision.mood,
        moodConfidence: moodDecision.confidence,
        tags: tags,
      );

      if (aiResult['success'] == true) {
        final aiActionItems = List<String>.from(
          aiResult['ai_action_items'] ?? const [],
        );
        final safetyFlag =
            aiResult['safety_flag'] == true || aiResult['is_blocked'] == true;
        final crisisResources = List<String>.from(
          aiResult['crisis_resources'] ?? const [],
        );
        final updatedEntry = JournalEntry(
          id: entry.id,
          timestamp: entry.timestamp,
          transcript: entry.transcript,
          summary: entry.summary,
          mood: entry.mood,
          moodConfidence: entry.moodConfidence,
          tags: entry.tags,
          aiSummary: (aiResult['ai_summary'] as String?)?.trim(),
          aiActionItems: aiActionItems,
          aiMoodExplanation: (aiResult['ai_mood_explanation'] as String?)?.trim(),
          aiFollowupPrompt: (aiResult['ai_followup_prompt'] as String?)?.trim(),
          audioPath: entry.audioPath,
          isSynced: entry.isSynced,
        );
        await journalProvider.updateEntry(updatedEntry);

        if (aiActionItems.isNotEmpty) {
          final replacementItems = aiActionItems.asMap().entries.map((kv) {
            return ActionItem(
              id: '${entryId}_ai_${kv.key}',
              entryId: entryId,
              description: kv.value,
            );
          }).toList();
          await journalProvider.replaceActionItems(entryId, replacementItems);
        }

        if (mounted) {
          if (safetyFlag) {
            _showMessage('AI returned a safety-focused response for this entry.');
            await _showSafetySupportDialog(crisisResources);
          } else {
            _showMessage('AI reflection added to your entry.');
          }
        }
      } else {
        _handleAIFailure(aiResult);
      }

      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _togglePauseResume() async {
    if (_isSaving || !_isRecording) return;

    if (_isPaused) {
      try {
        if (!kIsWeb) {
          await _audioRecorder.resume();
        }
      } catch (_) {
        if (mounted) {
          _showMessage('Unable to resume recording.');
        }
        return;
      }
      if (_speechAvailable) {
        try {
          await _speechToText.listen(
            onResult: (result) {
              if (!mounted) return;
              setState(() {
                _liveTranscript = result.recognizedWords.trim();
              });
            },
            listenOptions: SpeechListenOptions(
              partialResults: true,
              listenMode: ListenMode.dictation,
              cancelOnError: false,
            ),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isPaused = false;
        _statusLabel = _speechAvailable ? 'Listening...' : 'Recording audio...';
      });
      _startTimer();
      return;
    }

    try {
      if (!kIsWeb) {
        await _audioRecorder.pause();
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to pause recording.');
      }
      return;
    }
    _timer?.cancel();
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    if (!mounted) return;
    setState(() {
      _isPaused = true;
      _statusLabel = 'Recording paused';
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showSafetySupportDialog(List<String> resources) async {
    if (!mounted || resources.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: const Text('Safety Support'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your entry is saved. Here are immediate support resources:',
                ),
                const SizedBox(height: 10),
                ...resources.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $item'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/settings');
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _handleAIFailure(Map<String, dynamic> aiResult) {
    final errorCode = (aiResult['error_code'] ?? '').toString();
    final message = (aiResult['user_message'] ?? aiResult['message'] ??
            'AI reflection unavailable right now.')
        .toString();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    if (errorCode == 'ai_disabled') {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ),
      );
      return;
    }

    if (errorCode == 'auth_required' ||
        message.toLowerCase().contains('sign in required')) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Sign In',
            onPressed: () {
              AccountAccessService.requireAccount(
                context,
                featureLabel: 'AI analysis',
              );
            },
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _buildSummary(String transcript) {
    final cleaned = transcript.replaceAll('\n', ' ').trim();
    if (cleaned.isEmpty) return 'Voice Note';

    final sentenceSplit = cleaned.split(RegExp(r'[.!?]+'));
    final firstSentence = sentenceSplit
        .firstWhere((part) => part.trim().isNotEmpty, orElse: () => cleaned)
        .trim();
    if (firstSentence.length <= 64) return firstSentence;
    return '${firstSentence.substring(0, 64).trim()}...';
  }

  List<String> _buildTags(String transcript) {
    final lower = transcript.toLowerCase();
    final tags = <String>{};

    final keywordMap = <String, String>{
      'work': '#work',
      'project': '#project',
      'meeting': '#meeting',
      'team': '#teamwork',
      'goal': '#goals',
      'plan': '#planning',
      'routine': '#routine',
      'morning': '#morning',
      'run': '#health',
      'exercise': '#health',
      'focus': '#focus',
      'stress': '#stress',
      'grateful': '#gratitude',
      'family': '#family',
      'friend': '#relationships',
    };

    keywordMap.forEach((keyword, tag) {
      if (lower.contains(keyword)) {
        tags.add(tag);
      }
    });

    if (tags.isEmpty) {
      tags.add('#journal');
    }

    return tags.take(4).toList();
  }

  Mood _inferMood(String transcript) {
    final lower = transcript.toLowerCase();

    const positive = [
      'good',
      'great',
      'happy',
      'productive',
      'calm',
      'grateful',
      'excited',
      'motivated',
    ];
    const negative = [
      'bad',
      'sad',
      'tired',
      'stressed',
      'anxious',
      'overwhelmed',
      'angry',
      'frustrated',
    ];

    final positiveHits = positive.where(lower.contains).length;
    final negativeHits = negative.where(lower.contains).length;
    final score = positiveHits - negativeHits;

    if (score >= 2) return Mood.veryGood;
    if (score == 1) return Mood.good;
    if (score == 0) return Mood.neutral;
    if (score == -1) return Mood.bad;
    return Mood.veryBad;
  }

  void _startEnergySampling() {
    _energySamples.clear();
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 220))
        .listen((amplitude) {
          final normalized = _normalizeDecibel(amplitude.current);
          if (normalized.isFinite) {
            _energySamples.add(normalized);
          }
          if (_energySamples.length > 300) {
            _energySamples.removeRange(0, _energySamples.length - 300);
          }
        });
  }

  _MoodDecision _inferMoodDecision(String transcript) {
    final transcriptQuality = _transcriptQuality(transcript);
    final textScore = _textSentimentScore(transcript);
    final hasEnergySignal = _energySamples.length >= 8;
    final energyScore = hasEnergySignal ? _energySignalScore() : 0.0;

    if (transcriptQuality < 0.28 && textScore.abs() < 0.2) {
      final confidence = math.max(0.25, transcriptQuality * 0.6);
      return _MoodDecision(
        mood: Mood.neutral,
        confidence: confidence,
        usedEnergySignal: false,
      );
    }

    final energyWeight = hasEnergySignal ? 0.28 : 0.0;
    final textWeight = 1.0 - energyWeight;
    final signBias = textScore == 0 ? 1.0 : textScore.sign;
    final adjustedEnergy = energyScore * signBias;

    final combined = (textScore * textWeight) + (adjustedEnergy * energyWeight);
    final mood = _scoreToMood(combined);

    final evidenceStrength = combined.abs().clamp(0.0, 1.0);
    final energyReliability = hasEnergySignal
        ? (_energySamples.length / 40.0).clamp(0.0, 1.0)
        : 0.0;

    final confidence = (0.35 * transcriptQuality) +
        (0.45 * evidenceStrength) +
        (0.2 * energyReliability);

    return _MoodDecision(
      mood: mood,
      confidence: confidence.clamp(0.15, 0.98),
      usedEnergySignal: hasEnergySignal,
    );
  }

  double _transcriptQuality(String transcript) {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) return 0.0;
    if (cleaned.startsWith('Voice note recorded at ')) {
      return 0.0;
    }

    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return 0.0;

    final lexicalDiversity = words.toSet().length / words.length;
    final lengthScore = (words.length / 22.0).clamp(0.0, 1.0);
    return (0.7 * lengthScore) + (0.3 * lexicalDiversity);
  }

  double _textSentimentScore(String transcript) {
    final lower = transcript.toLowerCase();
    const weightedLexicon = <String, double>{
      'great': 0.9,
      'happy': 0.8,
      'grateful': 0.9,
      'calm': 0.7,
      'excited': 0.8,
      'motivated': 0.8,
      'productive': 0.7,
      'good': 0.5,
      'okay': 0.2,
      'fine': 0.2,
      'sad': -0.8,
      'bad': -0.6,
      'tired': -0.4,
      'stressed': -0.8,
      'anxious': -0.8,
      'overwhelmed': -0.9,
      'angry': -0.9,
      'frustrated': -0.7,
      'upset': -0.7,
      'lonely': -0.6,
    };

    double score = 0;
    double totalWeight = 0;
    weightedLexicon.forEach((token, weight) {
      if (lower.contains(token)) {
        score += weight;
        totalWeight += weight.abs();
      }
    });

    if (totalWeight == 0) {
      final fallback = _inferMood(transcript);
      switch (fallback) {
        case Mood.veryGood:
          return 0.75;
        case Mood.good:
          return 0.35;
        case Mood.neutral:
          return 0.0;
        case Mood.bad:
          return -0.35;
        case Mood.veryBad:
          return -0.75;
      }
    }

    return (score / totalWeight).clamp(-1.0, 1.0);
  }

  double _normalizeDecibel(double db) {
    final shifted = ((db + 60) / 60).clamp(0.0, 1.0);
    return shifted;
  }

  double _energySignalScore() {
    if (_energySamples.isEmpty) return 0.0;
    final avg =
        _energySamples.reduce((a, b) => a + b) / _energySamples.length;
    return ((avg - 0.5) * 2).clamp(-1.0, 1.0);
  }

  Mood _scoreToMood(double score) {
    if (score >= 0.55) return Mood.veryGood;
    if (score >= 0.18) return Mood.good;
    if (score <= -0.55) return Mood.veryBad;
    if (score <= -0.18) return Mood.bad;
    return Mood.neutral;
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

  List<ActionItem> _buildActionItems(String entryId, String transcript) {
    final sentences = transcript
        .split(RegExp(r'[.!?]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    final candidates = sentences
        .where(
          (item) => RegExp(
            r'\b(will|should|need to|plan to|next|tomorrow|must)\b',
            caseSensitive: false,
          ).hasMatch(item),
        )
        .take(2)
        .toList();

    if (candidates.isEmpty) {
      candidates.add('Review this voice note and define one clear next step.');
      if (sentences.isNotEmpty) {
        candidates.add('Follow up on: ${_buildSummary(sentences.first)}');
      }
    }

    return candidates.take(2).map((description) {
      return ActionItem(
        id: '${entryId}_${DateTime.now().microsecondsSinceEpoch}_${description.length}',
        entryId: entryId,
        description: description,
      );
    }).toList();
  }
}
