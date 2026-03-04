import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/journal_entry.dart';
import '../models/action_item.dart';

/// DatabaseService provides local persistence for journal entries and action items.
/// On native platforms (iOS, Android, macOS), it uses SQLite via sqflite.
/// On web, it falls back to an in-memory store since sqflite doesn't support web.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  // In-memory fallback for web
  static final List<Map<String, dynamic>> _memoryEntries = [];
  static final List<Map<String, dynamic>> _memoryActionItems = [];

  DatabaseService._init();

  bool get _isWeb => kIsWeb;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('calm_clarity.db');
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
      _memoryEntries.add(entry.toMap());
      return;
    }
    final db = await instance.database;
    await db.insert('journal_entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<JournalEntry>> getAllEntries() async {
    if (_isWeb) {
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
      final idx = _memoryEntries.indexWhere((m) => m['id'] == entry.id);
      if (idx != -1) {
        _memoryEntries[idx] = entry.toMap();
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
      _memoryEntries.removeWhere((m) => m['id'] == id);
      _memoryActionItems.removeWhere((m) => m['entryId'] == id);
      return;
    }
    final db = await instance.database;
    await db.delete('journal_entries', where: 'id = ?', whereArgs: [id]);
  }

  // ── Action Item CRUD ──

  Future<void> insertActionItem(ActionItem item) async {
    if (_isWeb) {
      _memoryActionItems.add(item.toMap());
      return;
    }
    final db = await instance.database;
    await db.insert('action_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ActionItem>> getActionItemsForEntry(String entryId) async {
    if (_isWeb) {
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
      final idx = _memoryActionItems.indexWhere((m) => m['id'] == id);
      if (idx != -1) {
        _memoryActionItems[idx]['isCompleted'] = isCompleted ? 1 : 0;
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
      _memoryActionItems.removeWhere((m) => m['entryId'] == entryId);
      _memoryActionItems.addAll(items.map((item) => item.toMap()));
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
