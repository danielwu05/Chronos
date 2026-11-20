import 'dart:io';

import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old version folders left by Chrome do not mark the extension outdated', () {
    final root = Directory.systemTemp.createTempSync('chronos_ext_ver');
    try {
      final id = BrowserExtensionInstaller.extensionId;
      for (final v in ['1.1.64_0', '1.1.67_0', '1.1.101_0']) {
        Directory('${root.path}/Default/Extensions/$id/$v').createSync(recursive: true);
      }
      final r = BrowserExtensionInstaller.inspectChromiumProfiles(root.path, expectedVersionOverride: '1.1.101');
      expect(r.hasOutdatedOrDisabled, isFalse);

      final old = BrowserExtensionInstaller.inspectChromiumProfiles(root.path, expectedVersionOverride: '1.1.102');
      expect(old.hasOutdatedOrDisabled, isTrue);
      expect(old.outdatedVersion, '1.1.101');
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
