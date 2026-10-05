import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/collection.dart';
import '../models/kind.dart';

/// A recent identification shown on the home screen, kept on the phone only.
class RecentIdentification {
  const RecentIdentification({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.nameEn,
    required this.nameBn,
    required this.confident,
  });

  final String id;
  final DateTime createdAt;
  final Kind? kind;
  final String nameEn;
  final String? nameBn;
  final bool confident;

  String name(String lang) => lang == 'bn' && nameBn != null && nameBn!.isNotEmpty ? nameBn! : nameEn;
}

/// The phone's own database: My Collection and reminders work with no network at all.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static const _version = 1;

  static Future<LocalDb> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'hobbylens.db'),
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          create table collection_items (
            id text primary key,
            kind text not null,
            taxon_id integer,
            identification_id text,
            scientific_name text,
            name_en text not null,
            name_bn text,
            nickname text,
            local_photo_path text,
            remote_photo_path text,
            notes text,
            care_json text,
            created_at text not null,
            updated_at text not null,
            deleted_at text,
            dirty integer not null default 1
          )''');
        await db.execute('''
          create table reminders (
            id text primary key,
            collection_item_id text not null references collection_items (id) on delete cascade,
            type text not null,
            label text,
            every_days integer,
            next_due text not null,
            remind_at text not null,
            notification_id integer not null unique,
            enabled integer not null default 1,
            updated_at text not null,
            deleted_at text,
            dirty integer not null default 1
          )''');
        await db.execute('''
          create table recents (
            id text primary key,
            created_at text not null,
            kind text,
            name_en text not null,
            name_bn text,
            confident integer not null
          )''');
        await db.execute('create table meta (key text primary key, value text)');
      },
      onConfigure: (db) => db.execute('pragma foreign_keys = on'),
    );
    return LocalDb._(db);
  }

  // Collection ---------------------------------------------------------------

  Future<List<CollectionItem>> collection() async {
    final rows = await _db.query('collection_items', where: 'deleted_at is null', orderBy: 'created_at desc');
    return rows.map(CollectionItem.fromDb).toList();
  }

  Future<CollectionItem?> collectionItem(String id) async {
    final rows = await _db.query('collection_items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CollectionItem.fromDb(rows.first);
  }

  Future<void> saveItem(CollectionItem item) => _upsert('collection_items', item.toDb());

  Future<bool> hasUnsyncedChanges() async {
    final a = Sqflite.firstIntValue(await _db.rawQuery('select count(*) from collection_items where dirty = 1')) ?? 0;
    final b = Sqflite.firstIntValue(await _db.rawQuery('select count(*) from reminders where dirty = 1')) ?? 0;
    return a + b > 0;
  }

  Future<List<CollectionItem>> dirtyItems() async {
    final rows = await _db.query('collection_items', where: 'dirty = 1');
    return rows.map(CollectionItem.fromDb).toList();
  }

  Future<void> purgeItem(String id) => _db.delete('collection_items', where: 'id = ?', whereArgs: [id]);

  // Reminders ----------------------------------------------------------------

  Future<List<Reminder>> remindersFor(String itemId) async {
    final rows = await _db.query(
      'reminders',
      where: 'collection_item_id = ? and deleted_at is null',
      whereArgs: [itemId],
      orderBy: 'next_due',
    );
    return rows.map(Reminder.fromDb).toList();
  }

  /// Every reminder not deleted, enabled or not (disabled ones need their notification cancelled).
  Future<List<Reminder>> liveReminders() async {
    final rows = await _db.query('reminders', where: 'deleted_at is null');
    return rows.map(Reminder.fromDb).toList();
  }

  /// All reminders of an item, including ones marked deleted, so notifications can be cancelled.
  Future<List<Reminder>> allRemindersFor(String itemId) async {
    final rows = await _db.query('reminders', where: 'collection_item_id = ?', whereArgs: [itemId]);
    return rows.map(Reminder.fromDb).toList();
  }

  Future<Reminder?> reminder(String id) async {
    final rows = await _db.query('reminders', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Reminder.fromDb(rows.first);
  }

  Future<void> saveReminder(Reminder r) => _upsert('reminders', r.toDb());

  /// Update-or-insert. Deliberately not INSERT OR REPLACE: REPLACE deletes the old row first,
  /// which would cascade-delete an item's reminders. (UPSERT syntax needs SQLite 3.24, newer
  /// than the SQLite in Android 9, so this is done in two steps inside a transaction.)
  Future<void> _upsert(String table, Map<String, Object?> row) {
    return _db.transaction((txn) async {
      final changed = await txn.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
      if (changed == 0) await txn.insert(table, row);
    });
  }

  Future<List<Reminder>> dirtyReminders() async {
    final rows = await _db.query('reminders', where: 'dirty = 1');
    return rows.map(Reminder.fromDb).toList();
  }

  Future<void> purgeReminder(String id) => _db.delete('reminders', where: 'id = ?', whereArgs: [id]);

  /// Notification id for a reminder that came from the server: keep the local one if known.
  Future<int?> notificationIdFor(String reminderId) async {
    final rows = await _db.query('reminders', columns: ['notification_id'], where: 'id = ?', whereArgs: [reminderId]);
    return rows.isEmpty ? null : rows.first['notification_id'] as int?;
  }

  // Recents --------------------------------------------------------------------

  Future<void> addRecent(RecentIdentification r) async {
    await _db.insert(
      'recents',
      {
        'id': r.id,
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'kind': r.kind?.name,
        'name_en': r.nameEn,
        'name_bn': r.nameBn,
        'confident': r.confident ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Keep the 20 most recent only.
    await _db.execute(
      'delete from recents where id not in (select id from recents order by created_at desc limit 20)',
    );
  }

  Future<List<RecentIdentification>> recents() async {
    final rows = await _db.query('recents', orderBy: 'created_at desc', limit: 20);
    return [
      for (final r in rows)
        RecentIdentification(
          id: r['id']! as String,
          createdAt: DateTime.parse(r['created_at']! as String),
          kind: Kind.tryParse(r['kind']),
          nameEn: r['name_en']! as String,
          nameBn: r['name_bn'] as String?,
          confident: r['confident'] == 1,
        ),
    ];
  }

  // Meta and reset -------------------------------------------------------------

  Future<String?> meta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) =>
      _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Removes everything stored on the phone (after account deletion or sign-out).
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete('reminders');
      await txn.delete('collection_items');
      await txn.delete('recents');
      await txn.delete('meta');
    });
  }
}
