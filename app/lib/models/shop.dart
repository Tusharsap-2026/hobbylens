enum ShopType {
  nursery('nursery'),
  petShop('pet_shop'),
  vetSupply('vet_supply'),
  vetClinic('vet_clinic');

  const ShopType(this.dbValue);
  final String dbValue;

  static ShopType parse(Object? v) => ShopType.values.firstWhere((t) => t.dbValue == v, orElse: () => ShopType.petShop);
}

/// One opening slot in local (Bangladesh) time, e.g. 09:00 to 21:00.
class HoursSlot {
  const HoursSlot(this.open, this.close);
  final String open;
  final String close;
}

class Shop {
  const Shop({
    required this.id,
    required this.nameEn,
    required this.nameBn,
    required this.type,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.addressEn,
    required this.addressBn,
    required this.area,
    required this.phone,
    required this.whatsapp,
    required this.hours,
    required this.openNow,
    required this.rating,
    required this.ratingCount,
    required this.verified,
    required this.isPartner,
    required this.categoryMatch,
    required this.inStock,
    required this.stockPriceBdt,
  });

  final String id;
  final String nameEn;
  final String? nameBn;
  final ShopType type;
  final double lat;
  final double lng;
  final int distanceM;
  final String? addressEn;
  final String? addressBn;
  final String? area;
  final String? phone;
  final String? whatsapp;

  /// Keys 'sat'..'fri'. Null when the shop's hours are unknown; a missing day means closed.
  final Map<String, List<HoursSlot>>? hours;
  final bool? openNow;
  final double? rating;
  final int ratingCount;
  final bool verified;
  final bool isPartner;
  final bool categoryMatch;
  final bool inStock;
  final int? stockPriceBdt;

  String name(String languageCode) =>
      languageCode == 'bn' && nameBn != null && nameBn!.isNotEmpty ? nameBn! : nameEn;

  String? address(String languageCode) =>
      languageCode == 'bn' && addressBn != null && addressBn!.isNotEmpty ? addressBn : addressEn;

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        id: json['id'] as String,
        nameEn: json['name_en'] as String? ?? '',
        nameBn: json['name_bn'] as String?,
        type: ShopType.parse(json['shop_type']),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
        addressEn: json['address_en'] as String?,
        addressBn: json['address_bn'] as String?,
        area: json['area'] as String?,
        phone: json['phone'] as String?,
        whatsapp: json['whatsapp'] as String?,
        hours: _parseHours(json['opening_hours']),
        openNow: json['open_now'] as bool?,
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        verified: json['verified_at'] != null,
        isPartner: json['is_partner'] == true,
        categoryMatch: json['category_match'] == true,
        inStock: json['in_stock'] == true,
        stockPriceBdt: (json['stock_price_bdt'] as num?)?.toInt(),
      );

  static Map<String, List<HoursSlot>>? _parseHours(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, List<HoursSlot>>{};
    raw.forEach((day, slots) {
      if (day is String && slots is List) {
        out[day] = [
          for (final s in slots)
            if (s is List && s.length == 2) HoursSlot('${s[0]}', '${s[1]}'),
        ];
      }
    });
    return out;
  }
}
