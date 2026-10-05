import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobbylens/l10n/app_localizations.dart';
import 'package:hobbylens/models/identify_result.dart';
import 'package:hobbylens/models/kind.dart';
import 'package:hobbylens/screens/result_screen.dart';
import 'package:hobbylens/services/photo_service.dart';

import 'fixtures.dart';

// A 1x1 transparent PNG, so Image.memory has something valid to decode.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=');

Widget _wrap(Widget child, String lang) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

ResultView _view(String fixtureName, RequestCategory requested) => ResultView(
      result: IdentifyResult.fromJson(fixture(fixtureName) as Map<String, dynamic>),
      photo: PickedPhoto(path: '/nonexistent.jpg', bytes: _png),
      requested: requested,
      onRetake: () {},
    );

void main() {
  for (final lang in ['bn', 'en']) {
    testWidgets('confident plant result renders in $lang on a small phone', (tester) async {
      // 360 dp wide, the width of common budget Android phones; tall enough that the whole
      // list is built, so every label can be checked.
      tester.view.physicalSize = const Size(720, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(_view('identify_confident_plant', RequestCategory.plant), lang));
      await tester.pumpAndSettle();
      expect(find.text(lang == 'bn' ? 'মানি প্ল্যান্ট' : 'Money plant (golden pothos)'), findsOneWidget);
      expect(find.text('Epipremnum aureum'), findsOneWidget);
      final l10n = lookupAppLocalizations(Locale(lang));
      expect(find.text(l10n.petSafeToxicBoth), findsOneWidget);
      expect(find.text(l10n.careDraft), findsOneWidget, reason: 'draft care must be labelled as unreviewed');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('low confidence shows the "not sure" screen, not an answer', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(_view('identify_low_confidence', RequestCategory.plant), 'en'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.lowConfidenceTitle), findsOneWidget);
    expect(find.text(l10n.possibleMatches), findsOneWidget);
    expect(find.text(l10n.saveToCollection), findsNothing);
  });

  testWidgets('a cat with a health concern shows the vet card', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(_view('identify_cat_vet', RequestCategory.cat), 'bn'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('bn'));
    expect(find.text(l10n.vetAdviceTitle), findsOneWidget);
    expect(find.text(l10n.bandHigh), findsOneWidget, reason: 'animals show a band, not a percentage');
  });
}
