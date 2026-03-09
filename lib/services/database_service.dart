import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/journal_entry.dart';
import '../models/action_item.dart';
import 'preferences_service.dart';

/// DatabaseService provides local persistence for journal entries and action items.
/// On native platforms (iOS, Android, macOS), it uses SQLite via sqflite.
/// On web, it stores data in SharedPreferences as JSON.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static String? _nativeDbScope;

  static const String _webEntriesKey = 'web_journal_entries';
  static const String _webActionItemsKey = 'web_action_items';
  static bool _webCacheLoaded = false;
  static String? _webCacheScope;

  // Web cache backed by SharedPreferences
  static final List<Map<String, dynamic>> _memoryEntries = [];
  static final List<Map<String, dynamic>> _memoryActionItems = [];

  DatabaseService._init();

  bool get _isWeb => kIsWeb;

  Future<String> _currentUserScope() async {
    final email = (await PreferencesService.getUserEmail()).trim().toLowerCase();
    if (email.isEmpty) {
      return 'guest';
    }
    return email;
  }

  String _scopedWebEntriesKey(String scope) => '$_webEntriesKey:$scope';
  String _scopedWebActionItemsKey(String scope) => '$_webActionItemsKey:$scope';

  Future<void> _ensureWebCacheLoaded() async {
    if (!_isWeb) return;

    final scope = await _currentUserScope();
    if (_webCacheLoaded && _webCacheScope == scope) return;

    final prefs = await SharedPreferences.getInstance();
    final scopedEntriesKey = _scopedWebEntriesKey(scope);
    final scopedActionItemsKey = _scopedWebActionItemsKey(scope);

    String? entriesRaw = prefs.getString(scopedEntriesKey);
    String? actionItemsRaw = prefs.getString(scopedActionItemsKey);

    if (entriesRaw == null && actionItemsRaw == null) {
      final legacyEntriesRaw = prefs.getString(_webEntriesKey);
      final legacyActionItemsRaw = prefs.getString(_webActionItemsKey);
      if (legacyEntriesRaw != null || legacyActionItemsRaw != null) {
        entriesRaw = legacyEntriesRaw;
        actionItemsRaw = legacyActionItemsRaw;
        if (legacyEntriesRaw != null) {
          await prefs.setString(scopedEntriesKey, legacyEntriesRaw);
        }
        if (legacyActionItemsRaw != null) {
          await prefs.setString(scopedActionItemsKey, legacyActionItemsRaw);
        }
      }
    }

    _memoryEntries
      ..clear()
      ..addAll(_decodeJsonList(entriesRaw));
    _memoryActionItems
      ..clear()
      ..addAll(_decodeJsonList(actionItemsRaw));

    _webCacheScope = scope;
    _webCacheLoaded = true;
  }

  List<Map<String, dynamic>> _decodeJsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistWebCache() async {
    if (!_isWeb) return;
    final scope = _webCacheScope ?? await _currentUserScope();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedWebEntriesKey(scope), jsonEncode(_memoryEntries));
    await prefs.setString(_scopedWebActionItemsKey(scope), jsonEncode(_memoryActionItems));
  }

  String _nativeDbFileForScope(String scope) {
    final normalized = scope.toLowerCase();
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final suffix = safe.isEmpty ? 'guest' : safe;
    return 'calm_clarity_$suffix.db';
  }

  Future<Database> get database async {
    if (_isWeb) {
      if (_database != null) return _database!;
      _database = await _initDB('calm_clarity.db');
      return _database!;
    }

    final scope = await _currentUserScope();
    if (_database != null && _nativeDbScope == scope) {
      return _database!;
    }

    if (_database != null && _nativeDbScope != scope) {
      await _database!.close();
      _database = null;
    }

    _database = await _initDB(_nativeDbFileForScope(scope));
    _nativeDbScope = scope;
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE journal_entries (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        transcript TEXT NOT NULL,
        summary TEXT NOT NULL,
        mood TEXT NOT NULL,
        moodConfidence REAL,
        tags TEXT NOT NULL,
        aiSummary TEXT,
        aiActionItems TEXT,
        aiMoodExplanation TEXT,
        aiFollowupPrompt TEXT,
        audioPath TEXT,
        isSynced INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE action_items (
        id TEXT PRIMARY KEY,
        entryId TEXT NOT NULL,
        description TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        dueDate TEXT,
        FOREIGN KEY (entryId) REFERENCES journal_entries (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN moodConfidence REAL',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN aiSummary TEXT',
      );
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN aiActionItems TEXT',
      );
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN aiMoodExplanation TEXT',
      );
      await db.execute(
        'ALTER TABLE journal_entries ADD COLUMN aiFollowupPrompt TEXT',
      );
    }
  }

  // ── Journal Entry CRUD ──

  Future<void> insertEntry(JournalEntry entry) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      final index = _memoryEntries.indexWhere((m) => m['id'] == entry.id);
      if (index == -1) {
        _memoryEntries.add(entry.toMap());
      } else {
        _memoryEntries[index] = entry.toMap();
      }
      await _persistWebCache();
      return;
    }
    final db = await instance.database;
    await db.insert('journal_entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<JournalEntry>> getAllEntries() async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      final sorted = List<Map<String, dynamic>>.from(_memoryEntries)
        ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      return sorted.map((m) => JournalEntry.fromMap(m)).toList();
    }
    final db = await instance.database;
    final result = await db.query('journal_entries', orderBy: 'timestamp DESC');
    return result.map((json) => JournalEntry.fromMap(json)).toList();
  }

  Future<void> updateEntry(JournalEntry entry) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      final idx = _memoryEntries.indexWhere((m) => m['id'] == entry.id);
      if (idx != -1) {
        _memoryEntries[idx] = entry.toMap();
        await _persistWebCache();
      }
      return;
    }
    final db = await instance.database;
    await db.update(
      'journal_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteEntry(String id) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      _memoryEntries.removeWhere((m) => m['id'] == id);
      _memoryActionItems.removeWhere((m) => m['entryId'] == id);
      await _persistWebCache();
      return;
    }
    final db = await instance.database;
    await db.delete('journal_entries', where: 'id = ?', whereArgs: [id]);
  }

  // ── Action Item CRUD ──

  Future<void> insertActionItem(ActionItem item) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      final index = _memoryActionItems.indexWhere((m) => m['id'] == item.id);
      if (index == -1) {
        _memoryActionItems.add(item.toMap());
      } else {
        _memoryActionItems[index] = item.toMap();
      }
      await _persistWebCache();
      return;
    }
    final db = await instance.database;
    await db.insert('action_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ActionItem>> getActionItemsForEntry(String entryId) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      return _memoryActionItems
          .where((m) => m['entryId'] == entryId)
          .map((m) => ActionItem.fromMap(m))
          .toList();
    }
    final db = await instance.database;
    final result = await db.query('action_items', where: 'entryId = ?', whereArgs: [entryId]);
    return result.map((json) => ActionItem.fromMap(json)).toList();
  }

  Future<void> updateActionItemStatus(String id, bool isCompleted) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      final idx = _memoryActionItems.indexWhere((m) => m['id'] == id);
      if (idx != -1) {
        _memoryActionItems[idx]['isCompleted'] = isCompleted ? 1 : 0;
        await _persistWebCache();
      }
      return;
    }
    final db = await instance.database;
    await db.update('action_items', {'isCompleted': isCompleted ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceActionItemsForEntry(
    String entryId,
    List<ActionItem> items,
  ) async {
    if (_isWeb) {
      await _ensureWebCacheLoaded();
      _memoryActionItems.removeWhere((m) => m['entryId'] == entryId);
      _memoryActionItems.addAll(items.map((item) => item.toMap()));
      await _persistWebCache();
      return;
    }

    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('action_items', where: 'entryId = ?', whereArgs: [entryId]);
      for (final item in items) {
        await txn.insert(
          'action_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> close() async {
    if (_isWeb) return;
    final db = _database;
    if (db != null) await db.close();
  }
}
