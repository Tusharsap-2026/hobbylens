import 'package:flutter_test/flutter_test.dart';
import 'package:hobbylens/models/accessory.dart';
import 'package:hobbylens/models/identify_result.dart';
import 'package:hobbylens/models/kind.dart';
import 'package:hobbylens/models/shop.dart';

import 'fixtures.dart';

void main() {
  group('identification response', () {
    test('confident plant: names, confidence, care and pet safety', () {
      final r = IdentifyResult.fromJson(fixture('identify_confident_plant') as Map<String, dynamic>);
      expect(r.status, IdStatus.confident);
      expect(r.detectedKind, Kind.plant);
      expect(r.matches, hasLength(3));
      final top = r.top!;
      expect(top.displayName('bn'), 'মানি প্ল্যান্ট');
      expect(top.displayName('en'), 'Money plant (golden pothos)');
      expect(top.confidence, closeTo(0.91, 1e-9));
      expect(top.band, Band.high);
      expect(top.petSafety, 'toxic_both');
      expect(top.care!.status, CareStatus.draft);
      expect(top.care!.tips.first.topic, 'light');
      expect(r.quotaLimit, 10);
    });

    test('a species outside our list falls back to its English name', () {
      final r = IdentifyResult.fromJson(fixture('identify_confident_plant') as Map<String, dynamic>);
      final second = r.matches[1];
      expect(second.taxonId, isNull);
      expect(second.displayName('bn'), 'Heartleaf philodendron');
    });

    test('low confidence is never reported as confident', () {
      final r = IdentifyResult.fromJson(fixture('identify_low_confidence') as Map<String, dynamic>);
      expect(r.status, IdStatus.lowConfidence);
      expect(r.top!.confidence! < 0.6, isTrue);
    });

    test('cat with a visible health concern asks for a vet', () {
      final r = IdentifyResult.fromJson(fixture('identify_cat_vet') as Map<String, dynamic>);
      expect(r.detectedKind, Kind.cat);
      expect(r.vetAdvice, isTrue);
      expect(r.top!.care!.isFallback, isTrue, reason: 'breeds fall back to the cat care card');
    });

    test('not recognised has no matches', () {
      final r = IdentifyResult.fromJson(fixture('identify_not_recognised') as Map<String, dynamic>);
      expect(r.status, IdStatus.notRecognised);
      expect(r.matches, isEmpty);
    });
  });

  test('nearby shops parse, partner stock first', () {
    final shops = (fixture('nearby_shops') as List<dynamic>).cast<Map<String, dynamic>>().map(Shop.fromJson).toList();
    expect(shops, isNotEmpty);
    expect(shops.first.inStock, isTrue);
    expect(shops.first.stockPriceBdt, 250);
    expect(shops.first.type, ShopType.nursery);
    expect(shops.first.whatsapp, startsWith('+8801'));
    expect(shops.first.hours!['sat']!.first.open, '09:00');
    expect(shops.first.name('bn'), 'ডেমো গ্রিন নার্সারি');
  });

  test('accessories parse, unpriced items keep null prices', () {
    final items = (fixture('accessories') as List<dynamic>).cast<Map<String, dynamic>>().map(Accessory.fromJson).toList();
    expect(items.where((a) => a.essential).map((a) => a.nameEn), contains('Cactus and succulent mix'));
    expect(items.every((a) => a.priceMinBdt == null), isTrue);
  });
}
