import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/collection.dart';
import '../models/identify_result.dart';
import '../models/kind.dart';
import 'local_db.dart';
import 'notification_service.dart';
import 'settings.dart';
import 'sync_service.dart';

/// My Collection and its reminders. Every change is written to the phone first, reminders are
/// scheduled locally, and the server is updated in the background.
class CollectionRepository extends ChangeNotifier {
  CollectionRepository(this._db, this._sync, this._notifications, this._settings);

  final LocalDb _db;
  final SyncService _sync;
  final NotificationService _notifications;
  final Settings _settings;
  final _uuid = const Uuid();

  Future<List<CollectionItem>> items() => _db.collection();
  Future<CollectionItem?> item(String id) => _db.collectionItem(id);
  Future<List<Reminder>> reminders(String itemId) => _db.remindersFor(itemId);

  Future<CollectionItem> saveFromResult({
    required IdMatch match,
    required Kind kind,
    required String identificationId,
    required String? photoPath,
  }) async {
    final id = _uuid.v4();
    String? localPhoto;
    if (photoPath != null && await File(photoPath).exists()) {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'collection'));
      await dir.create(recursive: true);
      localPhoto = (await File(photoPath).copy(p.join(dir.path, '$id.jpg'))).path;
    }
    final now = DateTime.now();
    final item = CollectionItem(
      id: id,
      kind: kind,
      taxonId: match.taxonId,
      identificationId: identificationId,
      scientificName: match.scientificName,
      nameEn: match.nameEn,
      nameBn: match.nameBn,
      nickname: null,
      localPhotoPath: localPhoto,
      remotePhotoPath: null,
      notes: null,
      care: match.care,
      createdAt: now,
      updatedAt: now,
    );
    await _db.saveItem(item);
    _changed();
    return item;
  }

  Future<void> rename(CollectionItem item, String? nickname) async {
    item.nickname = (nickname == null || nickname.trim().isEmpty) ? null : nickname.trim();
    await _touch(item);
    await rescheduleFor(item);
  }

  Future<void> delete(CollectionItem item) async {
    final now = DateTime.now();
    for (final r in await _db.remindersFor(item.id)) {
      await _notifications.cancel(r);
      r.deletedAt = now;
      r.updatedAt = now;
      r.dirty = true;
      await _db.saveReminder(r);
    }
    item.deletedAt = now;
    await _touch(item);
    if (item.localPhotoPath != null) {
      final f = File(item.localPhotoPath!);
      if (await f.exists()) await f.delete();
    }
  }

  Future<Reminder> addReminder({
    required CollectionItem item,
    required ReminderType type,
    required DateTime date,
    required int hour,
    required int minute,
    int? everyDays,
    String? label,
  }) async {
    final id = _uuid.v4();
    final r = Reminder(
      id: id,
      collectionItemId: item.id,
      type: type,
      label: (label == null || label.trim().isEmpty) ? null : label.trim(),
      everyDays: everyDays,
      nextDue: DateTime(date.year, date.month, date.day),
      hour: hour,
      minute: minute,
      notificationId: notificationIdFor(id),
      updatedAt: DateTime.now(),
    );
    // A repeating reminder whose first time has already passed today starts at its next date.
    r.rollForward(DateTime.now());
    await _db.saveReminder(r);
    await _schedule(r, item);
    _changed();
    return r;
  }

  /// Marks a reminder done: a repeating one moves to its next date, a one-off is removed.
  Future<void> markDone(Reminder r) async {
    final item = await _db.collectionItem(r.collectionItemId);
    if (r.everyDays == null) {
      r.deletedAt = DateTime.now();
      await _notifications.cancel(r);
    } else {
      final today = DateTime.now();
      r.nextDue = DateTime(today.year, today.month, today.day + r.everyDays!);
      if (item != null) await _schedule(r, item);
    }
    r.updatedAt = DateTime.now();
    r.dirty = true;
    await _db.saveReminder(r);
    _changed();
  }

  Future<void> deleteReminder(Reminder r) async {
    await _notifications.cancel(r);
    r.deletedAt = DateTime.now();
    r.updatedAt = DateTime.now();
    r.dirty = true;
    await _db.saveReminder(r);
    _changed();
  }

  /// Rolls repeating reminders forward and (re)schedules every notification. Called at start-up,
  /// after a sync and when the language changes, so titles match the chosen language.
  Future<void> rescheduleAll() async {
    final now = DateTime.now();
    for (final r in await _db.liveReminders()) {
      final item = await _db.collectionItem(r.collectionItemId);
      if (item == null || item.deletedAt != null) continue;
      final before = Reminder.dateOnly(r.nextDue);
      final stillDue = r.rollForward(now);
      if (Reminder.dateOnly(r.nextDue) != before) {
        r.updatedAt = now;
        r.dirty = true;
        await _db.saveReminder(r);
      }
      if (stillDue) {
        await _schedule(r, item); // also cancels the notification of a disabled reminder
      } else {
        await _notifications.cancel(r);
      }
    }
  }

  Future<void> rescheduleFor(CollectionItem item) async {
    for (final r in await _db.remindersFor(item.id)) {
      await _schedule(r, item);
    }
  }

  /// Pushes local changes and pulls changes from the user's other phones.
  Future<void> sync() async {
    await _sync.sync();
    await rescheduleAll();
    notifyListeners();
  }

  Future<bool> hasUnsyncedChanges() => _db.hasUnsyncedChanges();

  /// Wipes the phone's copy (used after sign-out or account deletion).
  Future<void> clearLocal() async {
    await _notifications.cancelAll();
    final items = await _db.collection();
    for (final i in items) {
      if (i.localPhotoPath != null) {
        final f = File(i.localPhotoPath!);
        if (await f.exists()) await f.delete();
      }
    }
    await _db.clearAll();
    notifyListeners();
  }

  Future<void> _touch(CollectionItem item) async {
    item.updatedAt = DateTime.now();
    item.dirty = true;
    await _db.saveItem(item);
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(sync());
  }

  Future<void> _schedule(Reminder r, CollectionItem item) async {
    final l10n = lookupAppLocalizations(Locale(_settings.languageCode));
    await _notifications.schedule(
      r,
      title: '${item.displayName(_settings.languageCode)}: ${reminderTypeLabel(l10n, r.type)}',
      body: r.label ?? l10n.notificationBody,
      channelName: l10n.reminders,
    );
  }
}

String reminderTypeLabel(AppLocalizations l10n, ReminderType t) => switch (t) {
      ReminderType.water => l10n.reminderWater,
      ReminderType.fertilise => l10n.reminderFertilise,
      ReminderType.feed => l10n.reminderFeed,
      ReminderType.groom => l10n.reminderGroom,
      ReminderType.vaccinate => l10n.reminderVaccinate,
      ReminderType.custom => l10n.reminderCustom,
    };
