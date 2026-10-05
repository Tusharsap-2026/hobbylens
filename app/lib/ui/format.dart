import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/identify_result.dart';
import '../models/kind.dart';
import '../models/shop.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
}

/// Numbers in the reader's digits (Bangla digits for Bangla).
String formatNumber(BuildContext context, num value, {int decimals = 0}) {
  final f = NumberFormat.decimalPattern(context.lang)
    ..minimumFractionDigits = decimals
    ..maximumFractionDigits = decimals;
  return f.format(value);
}

String formatPercent(BuildContext context, double fraction) =>
    NumberFormat.percentPattern(context.lang).format(fraction);

String formatDistance(BuildContext context, int metres) {
  final l10n = context.l10n;
  if (metres < 1000) return l10n.distanceM(formatNumber(context, (metres / 10).round() * 10));
  return l10n.distanceKm(formatNumber(context, metres / 1000, decimals: 1));
}

String formatTaka(BuildContext context, int amount) => formatNumber(context, amount);

String formatDate(BuildContext context, DateTime date) => DateFormat.yMMMd(context.lang).format(date);

String formatTime(BuildContext context, int hour, int minute) =>
    DateFormat.jm(context.lang).format(DateTime(2000, 1, 1, hour, minute));

String kindLabel(AppLocalizations l10n, Kind kind) => switch (kind) {
      Kind.plant => l10n.categoryPlant,
      Kind.cat => l10n.categoryCat,
      Kind.dog => l10n.categoryDog,
      Kind.bird => l10n.categoryBird,
    };

String categoryLabel(AppLocalizations l10n, RequestCategory c) => switch (c) {
      RequestCategory.plant => l10n.categoryPlant,
      RequestCategory.cat => l10n.categoryCat,
      RequestCategory.dog => l10n.categoryDog,
      RequestCategory.bird => l10n.categoryBird,
      RequestCategory.auto => l10n.categoryAuto,
    };

String bandLabel(AppLocalizations l10n, Band band) => switch (band) {
      Band.high => l10n.bandHigh,
      Band.medium => l10n.bandMedium,
      Band.low => l10n.bandLow,
    };

String topicLabel(AppLocalizations l10n, String topic) => switch (topic) {
      'light' => l10n.topicLight,
      'water' => l10n.topicWater,
      'soil' => l10n.topicSoil,
      'temperature' => l10n.topicTemperature,
      'fertiliser' => l10n.topicFertiliser,
      'food' => l10n.topicFood,
      'space' => l10n.topicSpace,
      'grooming' => l10n.topicGrooming,
      'exercise' => l10n.topicExercise,
      'vaccination' => l10n.topicVaccination,
      _ => topic,
    };

String shopTypeLabel(AppLocalizations l10n, ShopType t) => switch (t) {
      ShopType.nursery => l10n.shopNursery,
      ShopType.petShop => l10n.shopPetShop,
      ShopType.vetSupply => l10n.shopVetSupply,
      ShopType.vetClinic => l10n.shopVetClinic,
    };

/// Pet-safety line for a plant, or null when there is nothing to say.
String? petSafetyLabel(AppLocalizations l10n, String? value) => switch (value) {
      'safe' => l10n.petSafeSafe,
      'toxic_both' => l10n.petSafeToxicBoth,
      'toxic_cats' => l10n.petSafeToxicCats,
      'toxic_dogs' => l10n.petSafeToxicDogs,
      'unknown' => l10n.petSafeUnknown,
      _ => null,
    };
