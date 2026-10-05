class Accessory {
  const Accessory({
    required this.id,
    required this.categorySlug,
    required this.categoryEn,
    required this.categoryBn,
    required this.nameEn,
    required this.nameBn,
    required this.descriptionEn,
    required this.descriptionBn,
    required this.priceMinBdt,
    required this.priceMaxBdt,
    required this.essential,
  });

  final int id;
  final String categorySlug;
  final String categoryEn;
  final String categoryBn;
  final String nameEn;
  final String nameBn;
  final String? descriptionEn;
  final String? descriptionBn;
  final int? priceMinBdt;
  final int? priceMaxBdt;
  final bool essential;

  String name(String lang) => lang == 'bn' ? nameBn : nameEn;
  String category(String lang) => lang == 'bn' ? categoryBn : categoryEn;
  String? description(String lang) => lang == 'bn' ? descriptionBn : descriptionEn;

  factory Accessory.fromJson(Map<String, dynamic> json) => Accessory(
        id: (json['item_id'] as num).toInt(),
        categorySlug: json['category_slug'] as String? ?? '',
        categoryEn: json['category_name_en'] as String? ?? '',
        categoryBn: json['category_name_bn'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        nameBn: json['name_bn'] as String? ?? '',
        descriptionEn: json['description_en'] as String?,
        descriptionBn: json['description_bn'] as String?,
        priceMinBdt: (json['price_min_bdt'] as num?)?.toInt(),
        priceMaxBdt: (json['price_max_bdt'] as num?)?.toInt(),
        essential: json['essential'] == true,
      );
}
