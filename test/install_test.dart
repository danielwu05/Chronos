import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';

void main() {
  test('installAll successfully configures extensions across detected browsers', () async {
    final tmpHome = Directory.systemTemp.createTempSync('chronos_install_test_');
    addTearDown(() => tmpHome.deleteSync(recursive: true));
    Directory('${tmpHome.path}/.config/google-chrome/Default').createSync(recursive: true);
    Directory('${tmpHome.path}/.config/chromium/Default').createSync(recursive: true);

    final res = await BrowserExtensionInstaller.installAll(
      isAntiCheatActive: false,
      forceMandatory: true,
      homeOverride: tmpHome.path,
    );
    expect(res.success, isTrue);
    expect(res.browsers.isNotEmpty, isTrue);
  });
}
