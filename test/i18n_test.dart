import 'dart:convert';
import 'dart:io';

import 'package:chronos_app/l10n/app_localizations.dart';
import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all ARB files have the same keys and placeholders', () {
    Map<String, dynamic> load(String f) => jsonDecode(File('lib/l10n/$f').readAsStringSync()) as Map<String, dynamic>;
    final pt = load('app_pt.arb');
    final keys = pt.keys.where((k) => !k.startsWith('@')).toSet();
    final ph = RegExp(r'\{p\d+\}');
    for (final f in ['app_en.arb', 'app_zh.arb', 'app_zh_Hant.arb']) {
      final other = load(f);
      final otherKeys = other.keys.where((k) => !k.startsWith('@')).toSet();
      expect(otherKeys, equals(keys), reason: f);
      for (final k in keys) {
        final a = ph.allMatches(pt[k] as String).map((m) => m[0]).toSet();
        final b = ph.allMatches(other[k] as String).map((m) => m[0]).toSet();
        expect(b, equals(a), reason: '$f:$k');
      }
    }
  });

  test('language codes map to locales and translations', () {
    expect(lookupAppLocalizations(localeForCode('pt-BR')).configuracoes, 'Configurações');
    expect(lookupAppLocalizations(localeForCode('en-US')).configuracoes, 'Settings');
    expect(lookupAppLocalizations(localeForCode('zh-Hans')).configuracoes, '设置');
    expect(lookupAppLocalizations(localeForCode('zh-Hant')).configuracoes, '設定');
    setAppLanguageCode('en-US');
    expect(tr.cancelar, 'Cancel');
    setAppLanguageCode('pt-BR');
    expect(tr.cancelar, 'Cancelar');
  });
}
