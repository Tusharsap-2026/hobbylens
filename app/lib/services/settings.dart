import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences kept on the phone: language and whether first-run screens were seen.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const _kLanguage = 'language';
  static const _kOnboarded = 'onboarded';
  static const _kLocationExplained = 'location_explained';

  /// 'bn' or 'en'. Bangla is the default.
  String get languageCode => _prefs.getString(_kLanguage) ?? 'bn';

  Future<void> setLanguage(String code) async {
    if (code != 'bn' && code != 'en') return;
    await _prefs.setString(_kLanguage, code);
    notifyListeners();
  }

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded() async {
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  /// Whether the "why we need your location" card has been accepted once.
  bool get locationExplained => _prefs.getBool(_kLocationExplained) ?? false;

  Future<void> setLocationExplained() => _prefs.setBool(_kLocationExplained, true);
}
