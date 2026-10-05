import 'dart:convert';

import 'identify_result.dart';
import 'kind.dart';

/// A plant or pet the user owns. Stored on the phone first (works offline) and synced to the
/// server when the user is signed in and online.
class CollectionItem {
  CollectionItem({
    required this.id,
    required this.kind,
    required this.taxonId,
    required this.identificationId,
    required this.scientificName,
    required this.nameEn,
    required this.nameBn,
    required this.nickname,
    required this.localPhotoPath,
    required this.remotePhotoPath,
    required this.notes,
    required this.care,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.dirty = true,
  });

  final String id;
  final Kind kind;
  final int? taxonId;
  final String? identificationId;
  final String? scientificName;
  final String nameEn;
  final String? nameBn;
  String? nickname;
  String? localPhotoPath;
  String? remotePhotoPath;
  String? notes;
  final CareCard? care;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;
  bool dirty;

  String displayName(String lang) {
    if (nickname != null && nickname!.trim().isNotEmpty) return nickname!.trim();
    return lang == 'bn' && nameBn != null && nameBn!.isNotEmpty ? nameBn! : nameEn;
  }

  String speciesName(String lang) => lang == 'bn' && nameBn != null && nameBn!.isNotEmpty ? nameBn! : nameEn;

  Map<String, Object?> toDb() => {
        'id': id,
        'kind': kind.name,
        'taxon_id': taxonId,
        'identification_id': identificationId,
        'scientific_name': scientificName,
        'name_en': nameEn,
        'name_bn': nameBn,
        'nickname': nickname,
        'local_photo_path': localPhotoPath,
        'remote_photo_path': remotePhotoPath,
        'notes': notes,
        'care_json': care == null ? null : jsonEncode(care!.toJson()),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'dirty': dirty ? 1 : 0,
      };

  factory CollectionItem.fromDb(Map<String, Object?> row) => CollectionItem(
        id: row['id']! as String,
        kind: Kind.tryParse(row['kind']) ?? Kind.plant,
        taxonId: row['taxon_id'] as int?,
        identificationId: row['identification_id'] as String?,
        scientificName: row['scientific_name'] as String?,
        nameEn: row['name_en'] as String? ?? '',
        nameBn: row['name_bn'] as String?,
        nickname: row['nickname'] as String?,
        localPhotoPath: row['local_photo_path'] as String?,
        remotePhotoPath: row['remote_photo_path'] as String?,
        notes: row['notes'] as String?,
        care: _careFromJson(row['care_json'] as String?),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
        dirty: row['dirty'] == 1,
      );

  /// The server row (Supabase `collection_items`).
  Map<String, Object?> toRemote() => {
        'id': id,
        'kind': kind.name,
        'taxon_id': taxonId,
        'identification_id': identificationId,
        'scientific_name': scientificName,
        'name_en': nameEn,
        'name_bn': nameBn,
        'nickname': nickname,
        'photo_path': remotePhotoPath,
        'notes': notes,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory CollectionItem.fromRemote(Map<String, dynamic> row) => CollectionItem(
        id: row['id'] as String,
        kind: Kind.tryParse(row['kind']) ?? Kind.plant,
        taxonId: (row['taxon_id'] as num?)?.toInt(),
        identificationId: row['identification_id'] as String?,
        scientificName: row['scientific_name'] as String?,
        nameEn: row['name_en'] as String? ?? '',
        nameBn: row['name_bn'] as String?,
        nickname: row['nickname'] as String?,
        localPhotoPath: null,
        remotePhotoPath: row['photo_path'] as String?,
        notes: row['notes'] as String?,
        care: null,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at'] as String),
        dirty: false,
      );

  static CareCard? _careFromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    final decoded = jsonDecode(s);
    return decoded is Map<String, dynamic> ? CareCard.fromJson(decoded) : null;
  }
}

enum ReminderType {
  water,
  fertilise,
  feed,
  groom,
  vaccinate,
  custom;

  static ReminderType parse(Object? v) => ReminderType.values.firstWhere((t) => t.name == v, orElse: () => ReminderType.custom);

  static List<ReminderType> forKind(Kind kind) => kind == Kind.plant
      ? const [ReminderType.water, ReminderType.fertilise, ReminderType.custom]
      : const [ReminderType.feed, ReminderType.groom, ReminderType.vaccinate, ReminderType.custom];
}

/// A date the user entered for watering, feeding, vaccination and so on.
class Reminder {
  Reminder({
    required this.id,
    required this.collectionItemId,
    required this.type,
    required this.label,
    required this.everyDays,
    required this.nextDue,
    required this.hour,
    required this.minute,
    required this.notificationId,
    required this.updatedAt,
    this.enabled = true,
    this.deletedAt,
    this.dirty = true,
  });

  final String id;
  final String collectionItemId;
  final ReminderType type;
  String? label;

  /// Null for a one-off reminder.
  int? everyDays;

  /// Local calendar date (time part ignored).
  DateTime nextDue;
  int hour;
  int minute;

  /// Stable id for the phone's notification scheduler.
  final int notificationId;
  bool enabled;
  DateTime updatedAt;
  DateTime? deletedAt;
  bool dirty;

  DateTime get nextFireLocal => DateTime(nextDue.year, nextDue.month, nextDue.day, hour, minute);

  /// Moves a repeating reminder forward past [now]; returns false for a one-off that is over.
  bool rollForward(DateTime now) {
    if (everyDays == null || everyDays! < 1) return nextFireLocal.isAfter(now);
    var due = nextDue;
    while (DateTime(due.year, due.month, due.day, hour, minute).isBefore(now)) {
      due = DateTime(due.year, due.month, due.day + everyDays!);
    }
    nextDue = due;
    return true;
  }

  String get remindAt => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDate(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'collection_item_id': collectionItemId,
        'type': type.name,
        'label': label,
        'every_days': everyDays,
        'next_due': dateOnly(nextDue),
        'remind_at': remindAt,
        'notification_id': notificationId,
        'enabled': enabled ? 1 : 0,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'dirty': dirty ? 1 : 0,
      };

  factory Reminder.fromDb(Map<String, Object?> row) {
    final at = (row['remind_at'] as String? ?? '09:00').split(':');
    return Reminder(
      id: row['id']! as String,
      collectionItemId: row['collection_item_id']! as String,
      type: ReminderType.parse(row['type']),
      label: row['label'] as String?,
      everyDays: row['every_days'] as int?,
      nextDue: parseDate(row['next_due']! as String),
      hour: int.tryParse(at[0]) ?? 9,
      minute: at.length > 1 ? int.tryParse(at[1]) ?? 0 : 0,
      notificationId: row['notification_id']! as int,
      enabled: row['enabled'] == 1,
      updatedAt: DateTime.parse(row['updated_at']! as String),
      deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
      dirty: row['dirty'] == 1,
    );
  }

  Map<String, Object?> toRemote() => {
        'id': id,
        'collection_item_id': collectionItemId,
        'type': type.name,
        'label': label,
        'every_days': everyDays,
        'next_due': dateOnly(nextDue),
        'remind_at': '$remindAt:00',
        'enabled': enabled,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory Reminder.fromRemote(Map<String, dynamic> row, int notificationId) {
    final at = (row['remind_at'] as String? ?? '09:00:00').split(':');
    return Reminder(
      id: row['id'] as String,
      collectionItemId: row['collection_item_id'] as String,
      type: ReminderType.parse(row['type']),
      label: row['label'] as String?,
      everyDays: (row['every_days'] as num?)?.toInt(),
      nextDue: parseDate(row['next_due'] as String),
      hour: int.tryParse(at[0]) ?? 9,
      minute: at.length > 1 ? int.tryParse(at[1]) ?? 0 : 0,
      notificationId: notificationId,
      enabled: row['enabled'] != false,
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at'] as String),
      dirty: false,
    );
  }
}
