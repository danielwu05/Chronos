import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';

void main() {
  test('External Extensions descriptor uses signed external_crx without duplicate flags', () async {
    final tmpHome = Directory.systemTemp.createTempSync('chronos_features_test_');
    addTearDown(() => tmpHome.deleteSync(recursive: true));
    final home = tmpHome.path;
    Directory('$home/.config/chromium/Default').createSync(recursive: true);

    final report = await BrowserExtensionInstaller.installAllAutomatically(
      launchWithExtension: false,
      forceMandatory: true,
      homeOverride: home,
    );
    expect(report.success, isTrue);

    final extJson = File('$home/.config/chromium/External Extensions/${BrowserExtensionInstaller.extensionId}.json');
    expect(extJson.existsSync(), isTrue);
    final parsed = jsonDecode(extJson.readAsStringSync()) as Map<String, dynamic>;
    expect(parsed.containsKey('external_crx'), isTrue);
    expect(parsed.containsKey('external_path'), isFalse);

    final chromeFlags = File('$home/.config/chromium-flags.conf');
    if (chromeFlags.existsSync()) {
      final content = chromeFlags.readAsStringSync();
      expect(content.contains('--load-extension=') && content.contains('chronos'), isFalse);
    }
  });

  test('Auto-repair verifies extension status', () async {
    final tmpHome = Directory.systemTemp.createTempSync('chronos_repair_test_');
    addTearDown(() => tmpHome.deleteSync(recursive: true));
    Directory('${tmpHome.path}/.config/chromium/Default').createSync(recursive: true);

    final res = await BrowserExtensionInstaller.verifyAndAutoRepairExtensions(
      hasActiveSiteRules: false,
      homeOverride: tmpHome.path,
    );
    expect(res, isTrue);
  });

  test('Whitelist rich apps JSON serialization and deserialization', () {
    final payload = {
      'apps': [
        {'name': 'Counter-Strike 2', 'exec': 'steam'},
        {'name': 'Discord', 'exec': 'discord'}
      ],
      'sites': ['youtube.com', 'reels']
    };

    final jsonStr = jsonEncode(payload);
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(decoded['apps'], isA<List>());
    expect(decoded['sites'], isA<List>());
    expect((decoded['apps'] as List).first['name'], equals('Counter-Strike 2'));
    expect((decoded['apps'] as List).first['exec'], equals('steam'));
  });
}
