import 'dart:io';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart' show AppLocalizations;

/// App languages: Portuguese (default), English, Chinese Simplified and Traditional.
/// The code stored in the database (`primary_language`) maps to a Flutter [Locale].
const List<(String code, String label)> kAppLanguages = [
  ('pt-BR', 'Português (Brasil)'),
  ('en-US', 'English'),
  ('zh-Hans', '简体中文'),
  ('zh-Hant', '繁體中文'),
];

Locale localeForCode(String code) {
  switch (code) {
    case 'en-US':
      return const Locale('en');
    case 'zh-Hans':
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    case 'zh-Hant':
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    default:
      return const Locale('pt');
  }
}

/// Language code from the system locale (onboarding pre-selection).
String systemLanguageCode() {
  final raw = Platform.localeName.toLowerCase().replaceAll('_', '-');
  if (raw.startsWith('en')) return 'en-US';
  if (raw.startsWith('zh')) {
    return (raw.contains('hant') || raw.contains('-tw') || raw.contains('-hk') || raw.contains('-mo'))
        ? 'zh-Hant'
        : 'zh-Hans';
  }
  return 'pt-BR';
}

/// Current app locale; MaterialApp rebuilds when it changes.
final ValueNotifier<Locale> appLocale = ValueNotifier<Locale>(const Locale('pt'));

void setAppLanguageCode(String code) => appLocale.value = localeForCode(code);

/// Translations for the current locale, usable anywhere (also outside widgets).
AppLocalizations get tr => lookupAppLocalizations(appLocale.value);
