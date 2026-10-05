import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection.dart';
import 'auth_service.dart';
import 'local_db.dart';
import 'notification_service.dart';

/// Keeps My Collection and reminders in step with the server. The phone is the source of truth
/// while offline; each change is marked dirty and pushed later. Last write wins per row.
class SyncService {
  SyncService(this._client, this._db, this._auth, this._notifications);

  final SupabaseClient _client;
  final LocalDb _db;
  final AuthService _auth;
  final NotificationService _notifications;
  Future<void>? _running;
  bool _again = false;

  static const _timeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 60);
  static const _page = 500;

  /// Runs a sync if signed in with a phone; safe to call often and never throws. A call made
  /// while a sync is running schedules one more run, so edits made mid-sync are not left behind.
  Future<void> sync() {
    if (!_auth.isRegistered) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _loop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _runOnce();
    } while (_again && _auth.isRegistered);
  }

  Future<void> _runOnce() async {
    try {
      await _push();
      await _pull();
    } on SocketException {
      // Offline: try again next time.
    } on TimeoutException {
      // Slow network: try again next time.
    } catch (_) {
      // Server or auth problem: local data stays intact and dirty, so nothing is lost.
    }
  }

  Future<void> _push() async {
    final uid = _auth.user!.id;
    final photos = _client.storage.from('photos');
    for (final item in await _db.dirtyItems()) {
      if (item.deletedAt == null && item.remotePhotoPath == null && item.localPhotoPath != null) {
        final file = File(item.localPhotoPath!);
        if (await file.exists()) {
          final path = '$uid/collection/${item.id}.jpg';
          await photos
              .uploadBinary(path, await file.readAsBytes(), fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true))
              .timeout(_uploadTimeout);
          item.remotePhotoPath = path;
        }
      }
      await _client.from('collection_items').upsert(item.toRemote()).timeout(_timeout);
      if (item.deletedAt != null) {
        if (item.remotePhotoPath != null) await photos.remove([item.remotePhotoPath!]).timeout(_timeout);
      } else {
        item.dirty = false;
        await _db.saveItem(item);
      }
    }
    for (final r in await _db.dirtyReminders()) {
      await _client.from('reminders').upsert(r.toRemote()).timeout(_timeout);
      if (r.deletedAt != null) {
        await _db.purgeReminder(r.id);
      } else {
        r.dirty = false;
        await _db.saveReminder(r);
      }
    }
    // Items are purged locally only after their reminders were pushed, because deleting the
    // item row cascades to its reminders on the phone.
    for (final item in await _db.dirtyItems()) {
      if (item.deletedAt != null) await _db.purgeItem(item.id);
    }
  }

  Future<void> _pull() async {
    await _pullTable('collection_items', 'cursor_items', (row) async {
      final remote = CollectionItem.fromRemote(row);
      final local = await _db.collectionItem(remote.id);
      if (local != null && (local.dirty || !remote.updatedAt.isAfter(local.updatedAt))) return;
      if (remote.deletedAt != null) {
        for (final r in await _db.allRemindersFor(remote.id)) {
          await _notifications.cancel(r);
        }
        await _db.purgeItem(remote.id);
        return;
      }
      // Keep what only this phone knows: the local photo file and the cached care card.
      await _db.saveItem(CollectionItem(
        id: remote.id,
        kind: remote.kind,
        taxonId: remote.taxonId,
        identificationId: remote.identificationId,
        scientificName: remote.scientificName,
        nameEn: remote.nameEn,
        nameBn: remote.nameBn,
        nickname: remote.nickname,
        localPhotoPath: local?.localPhotoPath,
        remotePhotoPath: remote.remotePhotoPath,
        notes: remote.notes,
        care: local?.care,
        createdAt: remote.createdAt,
        updatedAt: remote.updatedAt,
        dirty: false,
      ));
    });

    await _pullTable('reminders', 'cursor_reminders', (row) async {
      final id = row['id'] as String;
      final local = await _db.reminder(id);
      final remote = Reminder.fromRemote(row, local?.notificationId ?? notificationIdFor(id));
      if (local != null && (local.dirty || !remote.updatedAt.isAfter(local.updatedAt))) return;
      if (remote.deletedAt != null) {
        if (local != null) await _notifications.cancel(local);
        await _db.purgeReminder(id);
        return;
      }
      if (await _db.collectionItem(remote.collectionItemId) == null) return;
      await _db.saveReminder(remote);
    });
  }

  /// Pages through rows changed since the stored cursor. The cursor is the newest server
  /// timestamp actually received, never the phone's clock, so no row is skipped.
  Future<void> _pullTable(
    String table,
    String cursorKey,
    Future<void> Function(Map<String, dynamic> row) apply,
  ) async {
    var cursor = await _db.meta(cursorKey) ?? '1970-01-01T00:00:00Z';
    while (true) {
      final rows = await _client
          .from(table)
          .select()
          .gt('updated_at', cursor)
          .order('updated_at', ascending: true)
          .range(0, _page - 1)
          .timeout(_timeout);
      for (final row in rows) {
        await apply(row);
        cursor = row['updated_at'] as String;
      }
      await _db.setMeta(cursorKey, cursor);
      if (rows.length < _page) break;
    }
  }
}

/// A stable 31-bit notification id derived from a reminder's UUID.
int notificationIdFor(String uuid) {
  var h = 0;
  for (final c in uuid.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}
