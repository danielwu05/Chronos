import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';

void main() {
  test('detectBrowsers finds installed browsers dynamically', () async {
    final browsers = await BrowserExtensionInstaller.detectBrowsers();
    expect(browsers.isNotEmpty, isTrue);
  });
}
