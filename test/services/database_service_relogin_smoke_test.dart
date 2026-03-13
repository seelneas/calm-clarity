import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calm_clarity/services/preferences_service.dart';
import 'package:calm_clarity/services/database_service.dart';
import 'package:calm_clarity/models/journal_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DatabaseService.debugForceWebStorage = true;
  });

  tearDown(() {
    DatabaseService.debugForceWebStorage = false;
  });

  test(
    'web-style scoped cache preserves same-user history across relogin intent',
    () async {
      SharedPreferences.setMockInitialValues({});

      await PreferencesService.setUserEmail('alice@example.com');

      final entry = JournalEntry(
        id: 'entry_1',
        timestamp: DateTime.parse('2026-03-08T10:00:00Z'),
        transcript: 'I felt calm and focused today.',
        summary: 'Calm day',
        mood: Mood.good,
        moodConfidence: 0.8,
        tags: const ['#focus'],
      );

      await DatabaseService.instance.insertEntry(entry);

      final before = await DatabaseService.instance.getAllEntries();
      expect(before.any((e) => e.id == 'entry_1'), isTrue);

      await PreferencesService.setUserName('');
      await PreferencesService.setUserEmail('');

      await PreferencesService.setUserEmail('alice@example.com');
      final afterRelogin = await DatabaseService.instance.getAllEntries();
      expect(afterRelogin.any((e) => e.id == 'entry_1'), isTrue);
    },
  );
}
