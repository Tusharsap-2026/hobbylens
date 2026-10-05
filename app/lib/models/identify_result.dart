import 'kind.dart';

enum IdStatus { confident, lowConfidence, notRecognised, failed }

IdStatus _status(Object? s) {
  switch (s) {
    case 'confident':
      return IdStatus.confident;
    case 'low_confidence':
      return IdStatus.lowConfidence;
    case 'not_recognised':
      return IdStatus.notRecognised;
    default:
      return IdStatus.failed;
  }
}

enum Band { high, medium, low }

Band _band(Object? b) {
  switch (b) {
    case 'high':
      return Band.high;
    case 'medium':
      return Band.medium;
    default:
      return Band.low;
  }
}

/// How the care text was produced, so the app can label it honestly.
enum CareStatus { reviewed, draft, aiGenerated }

CareStatus _careStatus(Object? s) {
  switch (s) {
    case 'reviewed':
      return CareStatus.reviewed;
    case 'ai_generated':
      return CareStatus.aiGenerated;
    default:
      return CareStatus.draft;
  }
}

class CareTip {
  const CareTip({required this.topic, required this.en, required this.bn});

  final String topic;
  final String en;
  final String bn;

  String text(String languageCode) => languageCode == 'bn' ? bn : en;

  factory CareTip.fromJson(Map<String, dynamic> json) => CareTip(
        topic: json['topic'] as String? ?? '',
        en: json['en'] as String? ?? '',
        bn: json['bn'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'topic': topic, 'en': en, 'bn': bn};
}

class CareCard {
  const CareCard({required this.status, required this.isFallback, required this.tips});

  final CareStatus status;
  final bool isFallback;
  final List<CareTip> tips;

  factory CareCard.fromJson(Map<String, dynamic> json) => CareCard(
        status: _careStatus(json['status']),
        isFallback: json['isFallback'] == true,
        tips: [
          for (final t in (json['tips'] as List<dynamic>? ?? const []))
            if (t is Map<String, dynamic>) CareTip.fromJson(t),
        ],
      );

  Map<String, dynamic> toJson() => {
        'status': switch (status) {
          CareStatus.reviewed => 'reviewed',
          CareStatus.draft => 'draft',
          CareStatus.aiGenerated => 'ai_generated',
        },
        'isFallback': isFallback,
        'tips': [for (final t in tips) t.toJson()],
      };
}

class IdMatch {
  const IdMatch({
    required this.rank,
    required this.taxonId,
    required this.taxonKey,
    required this.scientificName,
    required this.nameEn,
    required this.nameBn,
    required this.confidence,
    required this.band,
    required this.petSafety,
    required this.care,
  });

  final int rank;
  final int? taxonId;
  final String? taxonKey;
  final String scientificName;
  final String nameEn;
  final String? nameBn;
  final double? confidence;
  final Band band;
  final String? petSafety;
  final CareCard? care;

  /// Bangla name when the user reads Bangla and we have one; English otherwise.
  String displayName(String languageCode) =>
      languageCode == 'bn' && nameBn != null && nameBn!.isNotEmpty ? nameBn! : nameEn;

  factory IdMatch.fromJson(Map<String, dynamic> json) => IdMatch(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        taxonId: (json['taxonId'] as num?)?.toInt(),
        taxonKey: json['taxonKey'] as String?,
        scientificName: json['scientificName'] as String? ?? '',
        nameEn: json['nameEn'] as String? ?? '',
        nameBn: json['nameBn'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        band: _band(json['confidenceBand']),
        petSafety: json['petSafety'] as String?,
        care: json['care'] is Map<String, dynamic> ? CareCard.fromJson(json['care'] as Map<String, dynamic>) : null,
      );
}

class IdentifyResult {
  const IdentifyResult({
    required this.identificationId,
    required this.status,
    required this.requestedCategory,
    required this.detectedKind,
    required this.matches,
    required this.vetAdvice,
    required this.quotaUsed,
    required this.quotaLimit,
  });

  final String identificationId;
  final IdStatus status;
  final String requestedCategory;
  final Kind? detectedKind;
  final List<IdMatch> matches;
  final bool vetAdvice;
  final int quotaUsed;
  final int quotaLimit;

  IdMatch? get top => matches.isEmpty ? null : matches.first;

  factory IdentifyResult.fromJson(Map<String, dynamic> json) {
    final quota = json['quota'] is Map<String, dynamic> ? json['quota'] as Map<String, dynamic> : const <String, dynamic>{};
    return IdentifyResult(
      identificationId: json['identificationId'] as String? ?? '',
      status: _status(json['status']),
      requestedCategory: json['requestedCategory'] as String? ?? 'auto',
      detectedKind: Kind.tryParse(json['detectedCategory']),
      matches: [
        for (final m in (json['matches'] as List<dynamic>? ?? const []))
          if (m is Map<String, dynamic>) IdMatch.fromJson(m),
      ],
      vetAdvice: json['vetAdvice'] == true,
      quotaUsed: (quota['used'] as num?)?.toInt() ?? 0,
      quotaLimit: (quota['limit'] as num?)?.toInt() ?? 0,
    );
  }
}
