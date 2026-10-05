import 'package:flutter_test/flutter_test.dart';
import 'package:hobbylens/models/collection.dart';
import 'package:hobbylens/models/kind.dart';
import 'package:hobbylens/services/phone.dart';
import 'package:hobbylens/services/photo_service.dart';
import 'package:hobbylens/services/sync_service.dart';

void main() {
  group('Bangladeshi mobile numbers', () {
    test('accepts local, international and Bangla-digit forms', () {
      for (final input in ['01711223344', '+8801711223344', '8801711223344', '০১৭১১২২৩৩৪৪', '017-1122-3344']) {
        expect(normaliseBdMobile(input), '+8801711223344', reason: input);
      }
    });
    test('rejects landlines, short and foreign numbers', () {
      for (final input in ['0171122334', '+441711223344', '029123456', '01211223344', '']) {
        expect(normaliseBdMobile(input), isNull, reason: input);
      }
    });
  });

  group('on-device photo hint', () {
    test('routes a confident plant label to plant', () {
      final h = hintFromLabels([(label: 'Plant', confidence: 0.86), (label: 'Leaf', confidence: 0.7)]);
      expect(h.kind, Kind.plant);
      expect(h.confidence, 0.86);
      expect(h.looksUnrelated, isFalse);
    });
    test('picks the strongest animal', () {
      final h = hintFromLabels([(label: 'Dog', confidence: 0.62), (label: 'Cat', confidence: 0.91)]);
      expect(h.kind, Kind.cat);
    });
    test('warns only when something else is clearly in the photo', () {
      expect(hintFromLabels([(label: 'Car', confidence: 0.92)]).looksUnrelated, isTrue);
      expect(hintFromLabels([(label: 'Car', confidence: 0.5)]).looksUnrelated, isFalse);
      expect(hintFromLabels([]).looksUnrelated, isFalse);
    });
    test('serialises for the gateway', () {
      final json = hintFromLabels([(label: 'Bird', confidence: 0.777777)]).toJson();
      expect(json['category'], 'bird');
      expect(json['confidence'], 0.778);
    });
  });

  group('reminders', () {
    Reminder make({int? every, DateTime? due}) => Reminder(
          id: 'r1',
          collectionItemId: 'c1',
          type: ReminderType.water,
          label: null,
          everyDays: every,
          nextDue: due ?? DateTime(2026, 10, 1),
          hour: 9,
          minute: 0,
          notificationId: 1,
          updatedAt: DateTime(2026, 10, 1),
        );

    test('a repeating reminder rolls forward past now in whole intervals', () {
      final r = make(every: 7);
      expect(r.rollForward(DateTime(2026, 10, 16, 12)), isTrue);
      expect(r.nextDue, DateTime(2026, 10, 22));
    });
    test('a one-off reminder in the past is over', () {
      expect(make().rollForward(DateTime(2026, 10, 2)), isFalse);
    });
    test('round-trips through the phone database and matches the server format', () {
      final r = make(every: 3);
      final back = Reminder.fromDb(r.toDb());
      expect(back.nextDue, r.nextDue);
      expect(back.everyDays, 3);
      expect(r.toRemote()['next_due'], '2026-10-01');
      expect(r.toRemote()['remind_at'], '09:00:00');
    });
    test('the notification id is stable and positive', () {
      final a = notificationIdFor('8a8f1d2e-0000-4000-8000-000000000001');
      expect(a, notificationIdFor('8a8f1d2e-0000-4000-8000-000000000001'));
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThan(1 << 31));
    });
  });

  test('collection item round-trips through the phone database', () {
    final now = DateTime.utc(2026, 10, 5, 3);
    final item = CollectionItem(
      id: 'c1',
      kind: Kind.plant,
      taxonId: 3,
      identificationId: 'i1',
      scientificName: 'Epipremnum aureum',
      nameEn: 'Money plant',
      nameBn: 'মানি প্ল্যান্ট',
      nickname: '  ',
      localPhotoPath: null,
      remotePhotoPath: null,
      notes: null,
      care: null,
      createdAt: now,
      updatedAt: now,
    );
    final back = CollectionItem.fromDb(item.toDb());
    expect(back.displayName('bn'), 'মানি প্ল্যান্ট', reason: 'a blank nickname falls back to the species name');
    expect(back.dirty, isTrue);
    expect(back.toRemote()['name_bn'], 'মানি প্ল্যান্ট');
  });
}
