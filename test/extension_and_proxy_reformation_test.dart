import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:chronos_app/services/extension_packager.dart';
import 'package:chronos_app/services/web_block_server.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

void main() {
  group('ExtensionPackager & CRX3/XPI/PAC', () {
    test('Builds valid CRX3 v1.1.0+, XPI, Root CA, and fail-open PAC', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_pkg_test_');
      try {
        final res = await ExtensionPackager.packageAll(
          homeDirOverride: tmpHome.path,
          forceRebuild: true,
        );

        expect(res.success, isTrue, reason: res.message);
        // The fixed ID only exists where the signing key `chronos_extension.pem` is present
        // (gitignored, so absent in CI); otherwise a fresh key yields another valid ID.
        final root = ExtensionPackager.findProjectRoot();
        final hasSigningKey = root != null && File('$root/chronos_extension.pem').existsSync();
        if (hasSigningKey) {
          expect(res.extensionId, equals('jmbcpjljbgjabggbblfajojeahficjgi'));
        } else {
          expect(res.extensionId, matches(RegExp(r'^[a-p]{32}$')));
        }
        expect(ExtensionPackager.compareVersions(res.version, '1.1.0'), greaterThanOrEqualTo(0));

        // Verify CRX3 binary header: "Cr24" + version=3 LE
        final crxFile = File(res.guardCrxPath!);
        expect(crxFile.existsSync(), isTrue);
        final bytes = await crxFile.readAsBytes();
        expect(bytes.length, greaterThan(2048));
        expect(ascii.decode(bytes.sublist(0, 4)), equals('Cr24'));
        final version = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
        expect(version, equals(3));

        // Verify ZIP payload inside CRX3 contains modern extension files
        final headerLen = bytes[8] | (bytes[9] << 8) | (bytes[10] << 16) | (bytes[11] << 24);
        final zipBytes = bytes.sublist(12 + headerLen);
        final innerZip = File('${tmpHome.path}/extracted.zip');
        await innerZip.writeAsBytes(zipBytes);
        final listZip = await Process.run('unzip', ['-l', innerZip.path]);
        expect(listZip.exitCode, equals(0));
        final zipListing = listZip.stdout.toString();
        expect(zipListing, contains('focus_filters_core.js'));
        expect(zipListing, contains('focus_hud_panel.js'));
        expect(zipListing, contains('navigation_hook.js'));
        expect(zipListing, contains('content.js'));
        expect(zipListing, contains('background.js'));
        final expectedSw = 'sw_${res.version.replaceAll('.', '_')}.js';
        expect(zipListing, contains(expectedSw));
        final packagedManifest = jsonDecode(
          File('${tmpHome.path}/.local/share/chronos/extension/manifest.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(packagedManifest['background']?['service_worker'], equals(expectedSw));
        expect(zipListing, contains('popup.js'));
        // Without update_url Chrome asks the Web Store for updates and never upgrades.
        final crxManifest = jsonDecode(
          (await Process.run('unzip', ['-p', innerZip.path, 'manifest.json'])).stdout.toString(),
        ) as Map<String, dynamic>;
        expect(crxManifest['update_url'], equals(ExtensionPackager.chromiumUpdateUrl));

        // Verify Firefox XPI does not contain nested .xpi archives
        expect(res.xpiPath, isNotNull);
        final xpiList = await Process.run('unzip', ['-l', res.xpiPath!]);
        expect(xpiList.exitCode, equals(0));
        final xpiListing = xpiList.stdout.toString();
        expect(xpiListing, contains('focus_filters_core.js'));
        expect(xpiListing, contains('focus_hud_panel.js'));
        expect(xpiListing, isNot(contains('chronos_blocker@chronos.local.xpi')));

        // Verify CA cert & fail-open PAC
        expect(res.caCertPath, isNotNull);
        expect(File(res.caCertPath!).readAsStringSync(), contains('BEGIN CERTIFICATE'));
        expect(res.pacPath, isNotNull);
        final pacText = File(res.pacPath!).readAsStringSync();
        expect(pacText, contains('PROXY 127.0.0.1:4546; DIRECT'));
        expect(pacText, contains('isPlainHostName(host)'));
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });
  });

  group('WebBlockServer & Flatpak / Honest Browser Detection', () {
    test('buildProxyPacContent returns fail-open local bypass PAC', () {
      final pac = WebBlockServer.buildProxyPacContent(proxyPort: 4546);
      expect(pac, contains('return "DIRECT";'));
      expect(pac, contains('return "PROXY 127.0.0.1:4546; DIRECT";'));
    });

    test('detectInstalledBrowsers preserves Flatpak App IDs cleanly', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_fp_detect_');
      try {
        await Directory('${tmpHome.path}/.var/app/com.google.Chrome/config/google-chrome')
            .create(recursive: true);
        await Directory('${tmpHome.path}/.var/app/org.mozilla.firefox/.mozilla/firefox')
            .create(recursive: true);

        final detected = await BrowserExtensionInstaller.detectInstalledBrowsers(
          homeOverride: tmpHome.path,
          flatpakListOutputOverride: 'com.google.Chrome\norg.mozilla.firefox\n',
          skipBinaryCheckForTest: true,
        );

        final fpChrome = detected.where((b) => b.id == 'flatpak:chrome').toList();
        final fpFirefox = detected.where((b) => b.id == 'flatpak:firefox').toList();
        expect(fpChrome.length, equals(1));
        expect(fpChrome.first.isFlatpak, isTrue);
        expect(fpChrome.first.flatpakAppId, equals('com.google.Chrome'));
        expect(fpChrome.first.executable, equals('flatpak run com.google.Chrome'));
        expect(fpChrome.first.isConfigured, isTrue);

        expect(fpFirefox.length, equals(1));
        expect(fpFirefox.first.isFlatpak, isTrue);
        expect(fpFirefox.first.flatpakAppId, equals('org.mozilla.firefox'));
        expect(fpFirefox.first.executable, equals('flatpak run org.mozilla.firefox'));
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('isExtensionInstalledInBrowser never trusts empty External Extensions stubs', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_honest_check_');
      try {
        final extStubDir = Directory('${tmpHome.path}/brave/External Extensions');
        await extStubDir.create(recursive: true);
        await File('${extStubDir.path}/${BrowserExtensionInstaller.extensionId}.json')
            .writeAsString('{"external_path":"/fake"}');

        final braveWithoutPrefs = DetectedBrowser(
          id: 'thorium', // policy dir unlikely to exist on test machine
          name: 'Test Chromium',
          family: 'chromium',
          executable: 'thorium-browser',
          configDir: '${tmpHome.path}/brave',
          policyPath: '${tmpHome.path}/nonexistent-policy.json',
        );
        expect(BrowserExtensionInstaller.isExtensionInstalledInBrowser(braveWithoutPrefs), isFalse);

        // Now write real active Preferences entry -> must report true
        final defProfile = Directory('${tmpHome.path}/brave/Default');
        await defProfile.create(recursive: true);
        await File('${defProfile.path}/Preferences').writeAsString(jsonEncode({
          'extensions': {
            'settings': {
              BrowserExtensionInstaller.extensionId: {
                'state': 1,
                'disable_reasons': [],
              },
            },
          },
        }));
        expect(BrowserExtensionInstaller.isExtensionInstalledInBrowser(braveWithoutPrefs), isTrue);

        // Firefox without valid Proxy+CA policy and without active extensions.json -> false
        final ffProfile = Directory('${tmpHome.path}/ff/abc.default');
        await ffProfile.create(recursive: true);
        await File('${ffProfile.path}/extensions.json').writeAsString(jsonEncode({
          'addons': [
            {
              'id': 'chronos_blocker@chronos.local', // legacy wrong ID
              'active': true,
            }
          ],
        }));
        final ffBrowser = DetectedBrowser(
          id: 'firefox',
          name: 'Firefox',
          family: 'firefox',
          executable: 'firefox',
          configDir: '${tmpHome.path}/ff',
          policyPath: '${tmpHome.path}/nonexistent-ff-policy.json',
        );
        // homeOverride: never look at the real Firefox profiles of the machine running the tests.
        expect(BrowserExtensionInstaller.isExtensionInstalledInBrowser(ffBrowser, homeOverride: tmpHome.path), isFalse);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('Stale 1.0.0_0 Chromium profile fails verification even when policy exists', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_stale_crx_');
      try {
        final cfgDir = Directory('${tmpHome.path}/google-chrome');
        final defProfile = Directory('${cfgDir.path}/Default');
        final extVerDir = Directory(
          '${defProfile.path}/Extensions/${ExtensionPackager.defaultChromeExtensionId}/1.0.0_0',
        );
        await extVerDir.create(recursive: true);
        await File('${extVerDir.path}/manifest.json').writeAsString(
          jsonEncode({'name': 'Chronos', 'version': '1.0.0'}),
        );

        await File('${defProfile.path}/Preferences').writeAsString(jsonEncode({
          'extensions': {
            'settings': {
              ExtensionPackager.defaultChromeExtensionId: {
                'state': 1,
                'location': 7,
                'manifest': {'version': '1.0.0'},
              },
            },
          },
        }));

        final fakeCrx = File('${tmpHome.path}/chronos.crx');
        await fakeCrx.writeAsBytes([1, 2, 3]);
        final polFile = File('${tmpHome.path}/chronos-focus.json');
        await polFile.writeAsString(jsonEncode({
          'ExtensionInstallForcelist': [
            '${ExtensionPackager.defaultChromeExtensionId};file://${tmpHome.path}/update.xml',
          ],
        }));

        final browser = DetectedBrowser(
          id: 'chrome',
          name: 'Google Chrome',
          family: 'chromium',
          executable: 'google-chrome',
          configDir: cfgDir.path,
          policyPath: polFile.path,
        );

        final diag = BrowserExtensionInstaller.inspectChromiumProfiles(
          cfgDir.path,
          expectedVersionOverride: '1.1.3',
        );
        expect(diag.hasAnyEntry, isTrue);
        expect(diag.hasOutdatedOrDisabled, isTrue);
        expect(diag.outdatedVersion, equals('1.0.0'));
        expect(
          BrowserExtensionInstaller.isExtensionInstalledInBrowser(
            browser,
            expectedVersionOverride: '1.1.3',
          ),
          isFalse,
        );
        expect(BrowserExtensionInstaller.getBrowserPendingMessage(browser), isNotNull);

        // Once upgraded to 1.1.3 with valid state, verification passes cleanly (using real store or matching version).
        await extVerDir.delete(recursive: true);
        await File('${defProfile.path}/Preferences').writeAsString(jsonEncode({
          'extensions': {
            'settings': {
              ExtensionPackager.defaultChromeExtensionId: {
                'state': 1,
                'location': 2,
                'manifest': {'version': '99.0.0'},
              },
            },
          },
        }));
        final cleanDiag = BrowserExtensionInstaller.inspectChromiumProfiles(
          cfgDir.path,
          expectedVersionOverride: '99.0.0',
        );
        expect(cleanDiag.hasOutdatedOrDisabled, isFalse);
        expect(cleanDiag.hasActiveValid, isTrue);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('detectInstalledBrowsers finds Arch XDG ~/.config/mozilla/firefox profile dir', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_ff_xdg_');
      try {
        await Directory('${tmpHome.path}/.config/mozilla/firefox/abc.default-release')
            .create(recursive: true);

        final detected = await BrowserExtensionInstaller.detectInstalledBrowsers(
          homeOverride: tmpHome.path,
          flatpakListOutputOverride: '',
          skipBinaryCheckForTest: true,
        );

        final ff = detected.where((b) => b.id == 'firefox').toList();
        expect(ff.length, equals(1));
        expect(ff.first.configDir, equals('${tmpHome.path}/.config/mozilla/firefox'));
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('chrome://extensions, settings and about:addons are never blocked (even with anti-cheat)', () async {
      for (final filePath in ['chronos_extension/background.js', 'chronos_extension_firefox/background.js']) {
        final bgContent = File(filePath).readAsStringSync();
        expect(bgContent, contains('antiCheatActive'), reason: filePath);
        expect(bgContent, contains('maybeBlockProtectedBrowserPage'), reason: filePath);
      }

      // Run both Chrome & Firefox background scripts under a mocked chrome.* harness via Node when available.
      final whichNode = await Process.run('which', ['node']);
      if (whichNode.exitCode == 0) {
        final script = r'''
const fs = require("fs");
const vm = require("vm");

async function verifyScript(filePath, urlsToCheck) {
  const updates = [];
  const beforeNavListeners = [];
  const tabUpdateListeners = [];
  let statusAntiCheat = false;
  const storageData = {};

  const ctx = {
    console,
    URL,
    URLSearchParams,
    AbortController,
    setTimeout: () => 0,
    clearTimeout: () => {},
    setInterval: () => 0,
    importScripts: () => {},
    ChronosFocusCore: {
      buildFocusCss: () => "",
      getRedirectTarget: () => null,
    },
    fetch: async (url) => {
      if (String(url).includes("/api/status")) {
        return {
          ok: true,
          json: async () => ({
            online: true,
            antiCheatActive: statusAntiCheat,
            antiCheatMode: statusAntiCheat ? "CHALLENGE" : "OFF",
            sites: [{ entityId: "youtube", displayName: "YouTube", pattern: "youtube.com", remainingSeconds: 0, isBlocked: true }],
            focusFilters: {},
          }),
        };
      }
      return { ok: true, json: async () => ({}) };
    },
    chrome: {
      runtime: { lastError: null, onMessage: { addListener: () => {} } },
      storage: {
        local: {
          get: (keys, cb) => cb({ ...storageData }),
          set: (obj) => Object.assign(storageData, obj),
          remove: () => {},
        },
        session: { get: (k, cb) => cb({}), set: () => {}, remove: () => {} },
      },
      scripting: { insertCSS: async () => {}, removeCSS: async () => {} },
      windows: { getLastFocused: (o, cb) => cb({ focused: false }), onRemoved: { addListener: () => {} } },
      tabs: {
        query: (q, cb) => cb([]),
        update: (tabId, upd) => updates.push({ tabId, url: upd.url }),
        sendMessage: async () => {},
        onUpdated: { addListener: (fn) => tabUpdateListeners.push(fn) },
        onActivated: { addListener: () => {} },
        onRemoved: { addListener: () => {} },
      },
      webNavigation: {
        onBeforeNavigate: { addListener: (fn) => beforeNavListeners.push(fn) },
        onHistoryStateUpdated: { addListener: () => {} },
      },
      alarms: { create: () => {}, onAlarm: { addListener: () => {} } },
      action: { setBadgeText: () => {}, setBadgeBackgroundColor: () => {} },
      browserAction: { setBadgeText: () => {}, setBadgeBackgroundColor: () => {} },
    },
  };
  ctx.globalThis = ctx;

  vm.runInNewContext(fs.readFileSync(filePath, "utf8"), ctx);

  async function flushMicrotasks() {
    await new Promise((r) => setTimeout(r, 15));
  }

  await ctx.syncWithChronos();
  for (const url of urlsToCheck) {
    beforeNavListeners[0]({ frameId: 0, tabId: 10, url });
    tabUpdateListeners[0](10, { url }, { id: 10, title: "Settings" });
  }
  await flushMicrotasks();
  if (updates.length !== 0) {
    console.error("UNEXPECTED BLOCK WITH ANTI-CHEAT OFF:", filePath, updates);
    process.exit(1);
  }

  // Browser extension/settings pages stay open even with anti-cheat on (the force-installed
  // extension cannot be removed, and losing incognito access re-locks incognito).
  statusAntiCheat = true;
  await ctx.syncWithChronos();
  beforeNavListeners[0]({ frameId: 0, tabId: 11, url: urlsToCheck[0] });
  tabUpdateListeners[0](11, { url: urlsToCheck[0] }, { id: 11, title: "Extensions" });
  await flushMicrotasks();
  if (updates.length !== 0) {
    console.error("UNEXPECTED BLOCK WITH ANTI-CHEAT ON:", filePath, updates);
    process.exit(1);
  }
}

(async () => {
  await verifyScript("chronos_extension/background.js", ["chrome://extensions/", "chrome://settings/"]);
  await verifyScript("chronos_extension_firefox/background.js", ["about:addons", "about:preferences", "chrome://extensions/"]);
  console.log("ANTI_CHEAT_EXT_TEST_OK");
})();
''';
        final nodeRes = await Process.run('node', ['-e', script]);
        expect(nodeRes.exitCode, equals(0), reason: '${nodeRes.stdout}\n${nodeRes.stderr}');
        expect(nodeRes.stdout.toString(), contains('ANTI_CHEAT_EXT_TEST_OK'));
      }
    });
  });

  group('Mandatory Install & Anti-Burla Removal', () {
    test('Pending browser reports uninstalled and Aguardando Abrir/Reiniciar', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_pending_status_');
      try {
        final pkg = await ExtensionPackager.packageAll(homeDirOverride: tmpHome.path);
        expect(pkg.success, isTrue, reason: pkg.message);
        expect(pkg.crxPath, isNotNull);

        final cfgDir = Directory('${tmpHome.path}/thorium');
        await Directory('${cfgDir.path}/Default').create(recursive: true);
        final extDir = Directory('${cfgDir.path}/External Extensions');
        await extDir.create(recursive: true);
        await File('${extDir.path}/${BrowserExtensionInstaller.extensionId}.json')
            .writeAsString(jsonEncode({
          'external_crx': pkg.crxPath,
          'external_version': pkg.version,
        }));

        final browser = DetectedBrowser(
          id: 'thorium',
          name: 'Thorium',
          family: 'chromium',
          executable: 'thorium-browser',
          configDir: cfgDir.path,
          policyPath: '${tmpHome.path}/nonexistent-policy.json',
        );

        expect(
          BrowserExtensionInstaller.isExtensionInstalledInBrowser(
            browser,
            homeOverride: tmpHome.path,
          ),
          isFalse,
        );
        expect(
          BrowserExtensionInstaller.getBrowserPendingMessage(
            browser,
            homeOverride: tmpHome.path,
          ),
          isNotNull,
        );

        final desc = BrowserExtensionInstaller.describeBrowserStatus(
          browser,
          homeOverride: tmpHome.path,
        );
        expect(desc.installed, isFalse);
        expect(desc.statusLabel, equals('Aguardando Abrir/Reiniciar'));
        expect(desc.pendingMessage, isNotNull);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('verifyAntiCheatAndUninstall enforces Anti-Burla OFF before calling guard uninstall', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_guard_uninstall_');
      try {
        var runnerCalled = false;
        Future<ProcessResult> fakeRunner(String exe, List<String> args) async {
          runnerCalled = true;
          return ProcessResult(1, 0, 'uninstalled', '');
        }

        // Challenge active -> blocked
        final challengeRes = await ChronosGuardService.verifyAntiCheatAndUninstall(
          antiCheatProvider: () async => const AntiCheatStateDto(
            isActive: true,
            mode: 'CHALLENGE',
            nukeRemainingSeconds: 0,
            challengeText: 'type this',
          ),
          processRunner: fakeRunner,
          guardInstalledOverride: true,
          homeOverride: tmpHome.path,
        );
        expect(challengeRes.success, isFalse);
        expect(runnerCalled, isFalse);
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isFalse,
        );

        // Nuke active -> blocked with Nuke message
        final nukeRes = await ChronosGuardService.verifyAntiCheatAndUninstall(
          antiCheatProvider: () async => const AntiCheatStateDto(
            isActive: true,
            mode: 'NUKE',
            nukeRemainingSeconds: 120,
            challengeText: '',
          ),
          processRunner: fakeRunner,
          guardInstalledOverride: true,
          homeOverride: tmpHome.path,
        );
        expect(nukeRes.success, isFalse);
        expect(nukeRes.message, contains('Nuke'));
        expect(runnerCalled, isFalse);
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isFalse,
        );

        // Anti-Burla OFF -> invokes pkexec chronos-guard uninstall and cleans user browsers
        final invokedCalls = <(String, List<String>)>[];
        final offRes = await ChronosGuardService.verifyAntiCheatAndUninstall(
          antiCheatProvider: () async => const AntiCheatStateDto(
            isActive: false,
            mode: 'OFF',
            nukeRemainingSeconds: 0,
            challengeText: '',
          ),
          processRunner: (exe, args) async {
            invokedCalls.add((exe, args));
            return ProcessResult(1, 0, 'ok', '');
          },
          guardInstalledOverride: true,
          homeOverride: tmpHome.path,
        );
        expect(offRes.success, isTrue);
        expect(invokedCalls.length, equals(1));
        expect(invokedCalls.first.$1, equals('pkexec'));
        expect(
          invokedCalls.first.$2,
          equals(['--disable-internal-agent', ChronosGuardService.guardBinary, 'uninstall']),
        );
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isTrue,
        );
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('verifyAndAutoRepairExtensions respects .extension_removed_by_user when Anti-Burla is OFF and repairs when ON', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_removal_flag_');
      try {
        await Directory('${tmpHome.path}/.config/chromium/Default').create(recursive: true);

        final firstInstall = await BrowserExtensionInstaller.installAllAutomatically(
          launchWithExtension: false,
          forceMandatory: true,
          homeOverride: tmpHome.path,
        );
        expect(firstInstall.success, isTrue);
        final extJson = File(
          '${tmpHome.path}/.config/chromium/External Extensions/${BrowserExtensionInstaller.extensionId}.json',
        );
        expect(extJson.existsSync(), isTrue);

        await BrowserExtensionInstaller.removeExtensionFromUserBrowsers(
          homeOverride: tmpHome.path,
        );
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isTrue,
        );
        expect(extJson.existsSync(), isFalse);

        // Anti-Burla OFF -> stays removed, auto-repair does not reinstall
        await BrowserExtensionInstaller.verifyAndAutoRepairExtensions(
          hasActiveSiteRules: false,
          isAntiCheatActive: false,
          homeOverride: tmpHome.path,
        );
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isTrue,
        );
        expect(extJson.existsSync(), isFalse);

        // Anti-Burla ON -> flag is cleared and mandatory install restores descriptor
        await BrowserExtensionInstaller.verifyAndAutoRepairExtensions(
          hasActiveSiteRules: false,
          isAntiCheatActive: true,
          homeOverride: tmpHome.path,
        );
        expect(
          BrowserExtensionInstaller.hasUserRemovedExtensionFlag(homeOverride: tmpHome.path),
          isFalse,
        );
        expect(extJson.existsSync(), isTrue);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('ExtensionPackager.findProjectRoot resolves bundled <exe>/data/chronos_assets fallback', () async {
      final tmpBundle = await Directory.systemTemp.createTemp('chronos_bundle_assets_');
      try {
        final fakeExe = '${tmpBundle.path}/chronos_app';
        await File(fakeExe).writeAsString('');
        final assetsRoot = '${tmpBundle.path}/data/chronos_assets';
        await Directory('$assetsRoot/chronos_extension').create(recursive: true);
        await File('$assetsRoot/chronos_extension/manifest.json')
            .writeAsString('{"version":"1.1.5"}');
        await Directory('$assetsRoot/system/guard').create(recursive: true);
        await File('$assetsRoot/system/guard/chronos-guard').writeAsString('#!/usr/bin/env bash\n');

        final found = ExtensionPackager.findProjectRoot(executablePathOverride: fakeExe);
        expect(found, equals(assetsRoot));
      } finally {
        await tmpBundle.delete(recursive: true);
      }
    });

    test('describeBrowserStatus distinguishes Proxy Seletivo Ativo, Extensão + Proxy Ativos, and Chromium Extensão Ativa', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_ff_status_');
      try {
        final caFile = File('${tmpHome.path}/chronos-proxy-ca.crt');
        final pacFile = File('${tmpHome.path}/proxy.pac');
        await caFile.writeAsString('-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----\n');
        await pacFile.writeAsString('function FindProxyForURL(url, host) { return "DIRECT"; }');

        final ffPolFile = File('${tmpHome.path}/ff_policies.json');
        await ffPolFile.writeAsString(jsonEncode({
          'policies': {
            'DisablePrivateBrowsing': true,
            'Certificates': {'Install': [caFile.path]},
            'Proxy': {'Mode': 'autoConfig', 'AutoConfigURL': 'file://${pacFile.path}'},
          },
        }));

        final ffCfg = Directory('${tmpHome.path}/.mozilla/firefox/test.default');
        await ffCfg.create(recursive: true);

        final firefox = DetectedBrowser(
          id: 'firefox',
          name: 'Firefox',
          family: 'firefox',
          executable: 'firefox',
          configDir: '${tmpHome.path}/.mozilla/firefox',
        );

        final ffProxyOnly = BrowserExtensionInstaller.describeBrowserStatus(
          firefox,
          homeOverride: tmpHome.path,
          policyPathOverride: ffPolFile.path,
          sysCaPathOverride: caFile.path,
          sysPacPathOverride: pacFile.path,
        );
        expect(ffProxyOnly.installed, isTrue);
        expect(ffProxyOnly.statusLabel, equals('Proxy Seletivo Ativo'));

        // Fork or profile with both CA/PAC proxy AND active extensions.json addon
        final forkCfg = Directory('${tmpHome.path}/.librewolf/test.default');
        await forkCfg.create(recursive: true);
        await File('${forkCfg.path}/extensions.json').writeAsString(jsonEncode({
          'addons': [
            {
              'id': ExtensionPackager.firefoxAddonId,
              'active': true,
              'userDisabled': false,
              'appDisabled': false,
            }
          ],
        }));
        final librewolf = DetectedBrowser(
          id: 'librewolf',
          name: 'LibreWolf',
          family: 'firefox',
          executable: 'librewolf',
          configDir: '${tmpHome.path}/.librewolf',
        );
        final forkBoth = BrowserExtensionInstaller.describeBrowserStatus(
          librewolf,
          homeOverride: tmpHome.path,
          policyPathOverride: ffPolFile.path,
          sysCaPathOverride: caFile.path,
          sysPacPathOverride: pacFile.path,
        );
        expect(forkBoth.installed, isTrue);
        expect(forkBoth.statusLabel, equals('Extensão + Proxy Ativos'));

        // Missing policy & no addon -> Requer Guard/Proxy
        final unconfigured = BrowserExtensionInstaller.describeBrowserStatus(
          firefox,
          homeOverride: tmpHome.path,
          policyPathOverride: '${tmpHome.path}/missing_policies.json',
          sysCaPathOverride: caFile.path,
          sysPacPathOverride: pacFile.path,
        );
        expect(unconfigured.installed, isFalse);
        expect(unconfigured.statusLabel, equals('Requer Guard/Proxy'));

        // Active Chromium browser profile -> Extensão Ativa
        final chromeDir = Directory('${tmpHome.path}/.config/google-chrome/Default');
        await chromeDir.create(recursive: true);
        final expectedVer = BrowserExtensionInstaller.getExpectedExtensionVersion(
          homeOverride: tmpHome.path,
        );
        await File('${chromeDir.path}/Preferences').writeAsString(jsonEncode({
          'extensions': {
            'settings': {
              BrowserExtensionInstaller.extensionId: {
                'state': 1,
                'manifest': {'version': expectedVer},
              }
            }
          }
        }));
        final chrome = DetectedBrowser(
          id: 'google-chrome',
          name: 'Google Chrome',
          family: 'chromium',
          executable: 'google-chrome',
          configDir: '${tmpHome.path}/.config/google-chrome',
        );
        final chromeStatus = BrowserExtensionInstaller.describeBrowserStatus(
          chrome,
          homeOverride: tmpHome.path,
        );
        expect(chromeStatus.installed, isTrue);
        expect(chromeStatus.statusLabel, equals('Extensão Ativa'));
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('cleanupLegacyUserFirefoxPolicies deletes Chronos user policy while preserving non-Chronos policies', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_ff_legacy_');
      try {
        final legacyChronos = File('${tmpHome.path}/.mozilla/firefox/policies/policies.json');
        await legacyChronos.parent.create(recursive: true);
        await legacyChronos.writeAsString(jsonEncode({
          'policies': {
            'ExtensionSettings': {
              'chronos-focus@chronos.local': {'installation_mode': 'force_installed'}
            }
          }
        }));

        final foreignPolicy = File('${tmpHome.path}/.config/mozilla/firefox/policies/policies.json');
        await foreignPolicy.parent.create(recursive: true);
        await foreignPolicy.writeAsString(jsonEncode({
          'policies': {
            'ExtensionSettings': {
              'corporate-extension@example.org': {'installation_mode': 'normal_installed'}
            }
          }
        }));

        await BrowserExtensionInstaller.cleanupLegacyUserFirefoxPolicies(
          homeOverride: tmpHome.path,
        );

        expect(legacyChronos.existsSync(), isFalse);
        expect(foreignPolicy.existsSync(), isTrue);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('ChronosGuardService.installViaPkexec handles success, cancel (126), and missing agent (127)', () async {
      final tmpStage = await Directory.systemTemp.createTemp('chronos_pkexec_stage_');
      try {
        await File('${tmpStage.path}/install-guard.sh').writeAsString('#!/usr/bin/env bash\nexit 0\n');

        final recorded = <(String, List<String>)>[];
        final ok = await ChronosGuardService.installViaPkexec(
          stagingDirOverride: tmpStage.path,
          skipPrepareForTest: true,
          processRunner: (exe, args) async {
            recorded.add((exe, args));
            return ProcessResult(1, 0, 'installed', '');
          },
        );
        expect(ok.success, isTrue);
        expect(recorded.single.$1, equals('pkexec'));
        expect(recorded.single.$2.take(2), equals(['bash', '${tmpStage.path}/install-guard.sh']));
        expect(recorded.single.$2.last, equals(tmpStage.path));

        final cancelled = await ChronosGuardService.installViaPkexec(
          stagingDirOverride: tmpStage.path,
          skipPrepareForTest: true,
          processRunner: (exe, args) async => ProcessResult(1, 126, '', 'dismissed'),
        );
        expect(cancelled.success, isFalse);
        expect(cancelled.message, contains('cancelada'));

        final noAgent = await ChronosGuardService.installViaPkexec(
          stagingDirOverride: tmpStage.path,
          skipPrepareForTest: true,
          processRunner: (exe, args) async => ProcessResult(1, 127, '', 'no agent'),
        );
        expect(noAgent.success, isFalse);
        expect(noAgent.message, contains('Polkit'));
      } finally {
        await tmpStage.delete(recursive: true);
      }
    });

    test('ChronosGuardService.checkFirefoxProxyHealth validates CA sync, PAC target, and proxy probe', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_ff_health_');
      try {
        final userCa = File('${tmpHome.path}/.local/share/chronos/ca/chronos-proxy-ca.crt');
        final sysCa = File('${tmpHome.path}/sys_ca.crt');
        final sysPac = File('${tmpHome.path}/sys_proxy.pac');
        await userCa.parent.create(recursive: true);
        await userCa.writeAsString('-----BEGIN CERTIFICATE-----\nCERT_A\n-----END CERTIFICATE-----\n');
        await sysCa.writeAsString('-----BEGIN CERTIFICATE-----\nCERT_A\n-----END CERTIFICATE-----\n');
        await sysPac.writeAsString(
          'function FindProxyForURL(url, host) { return "PROXY 127.0.0.1:4546; DIRECT"; }',
        );

        final okHealth = await ChronosGuardService.checkFirefoxProxyHealth(
          homeOverride: tmpHome.path,
          sysCaPathOverride: sysCa.path,
          sysPacPathOverride: sysPac.path,
          portProbe: () async => true,
        );
        expect(okHealth.healthy, isTrue);
        expect(okHealth.caSynced, isTrue);
        expect(okHealth.pacValid, isTrue);
        expect(okHealth.proxyReachable, isTrue);

        // Divergent CA should flag caSynced=false and healthy=false
        await sysCa.writeAsString('-----BEGIN CERTIFICATE-----\nSTALE\n-----END CERTIFICATE-----\n');
        final staleHealth = await ChronosGuardService.checkFirefoxProxyHealth(
          homeOverride: tmpHome.path,
          sysCaPathOverride: sysCa.path,
          sysPacPathOverride: sysPac.path,
          portProbe: () async => true,
        );
        expect(staleHealth.caSynced, isFalse);
        expect(staleHealth.healthy, isFalse);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('ExtensionPackager preserves pre-signed Mozilla XPI when META-INF/mozilla.rsa is present', () async {
      final tmpHome = await Directory.systemTemp.createTemp('chronos_signed_xpi_');
      try {
        final dataDir = Directory('${tmpHome.path}/.local/share/chronos');
        await dataDir.create(recursive: true);

        final stageDir = Directory('${tmpHome.path}/stage');
        await Directory('${stageDir.path}/META-INF').create(recursive: true);
        await File('${stageDir.path}/manifest.json')
            .writeAsString('{"manifest_version":2,"name":"Test","version":"9.9.9"}');
        await File('${stageDir.path}/META-INF/mozilla.rsa').writeAsString('FAKE_MOZ_SIG');

        final preSignedPath = '${dataDir.path}/chronos-signed.xpi';
        final zipRes = await Process.run(
          'zip',
          ['-rq', preSignedPath, '.'],
          workingDirectory: stageDir.path,
        );
        expect(zipRes.exitCode, equals(0));
        expect(ExtensionPackager.xpiHasMozillaSignature(File(preSignedPath)), isTrue);

        final pkg = await ExtensionPackager.packageAll(
          homeDirOverride: tmpHome.path,
          forceRebuild: true,
        );
        expect(pkg.success, isTrue);
        expect(pkg.xpiPath, isNotNull);
        expect(ExtensionPackager.xpiHasMozillaSignature(File(pkg.xpiPath!)), isTrue);
        final guardXpi = File('${tmpHome.path}/.local/share/chronos/guard/build/chronos.xpi');
        expect(ExtensionPackager.xpiHasMozillaSignature(guardXpi), isTrue);
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('ChronosHudPanel shared across Chromium, Firefox, and Rust proxy works cleanly', () async {
      for (final dir in ['chronos_extension', 'chronos_extension_firefox']) {
        final manifest = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;
        final scriptsList = manifest['content_scripts'] as List<dynamic>;
        final mainScript = scriptsList
            .cast<Map<String, dynamic>>()
            .firstWhere((e) => (e['js'] as List<dynamic>).contains('content.js'));
        final jsOrder = (mainScript['js'] as List<dynamic>).cast<String>();
        final coreIdx = jsOrder.indexOf('focus_filters_core.js');
        final hudIdx = jsOrder.indexOf('focus_hud_panel.js');
        final contentIdx = jsOrder.indexOf('content.js');
        expect(coreIdx, greaterThanOrEqualTo(0));
        expect(hudIdx, greaterThan(coreIdx));
        expect(contentIdx, greaterThan(hudIdx));
      }

      for (final file in [
        'focus_filters_core.js',
        'focus_hud_panel.js',
        'content.js',
        'popup.html',
        'popup.js',
      ]) {
        expect(
          File('chronos_extension/$file').readAsStringSync(),
          equals(File('chronos_extension_firefox/$file').readAsStringSync()),
          reason: '$file must match across Chromium and Firefox extensions',
        );
      }

      final proxyRs = File('rust/src/proxy.rs').readAsStringSync();
      expect(
        proxyRs.contains('const FOCUS_HUD_PANEL_JS: &str = include_str!("../../chronos_extension/focus_hud_panel.js");'),
        isTrue,
      );
      expect(proxyRs.contains('ChronosHudPanel'), isTrue);

      final popupHtml = File('chronos_extension/popup.html').readAsStringSync();
      expect(
        popupHtml.indexOf('DETOX GLOBAL'),
        lessThan(popupHtml.indexOf('YOUTUBE')),
        reason: 'Detox Global must appear before YouTube in popup.html',
      );
      final settingsDart = File('lib/widgets/general_settings_view.dart').readAsStringSync();
      expect(
        settingsDart.indexOf('tr.detoxGlobalTodosOsSites'),
        lessThan(settingsDart.indexOf('tr.youtubeFocus')),
        reason: 'Detox Global must appear before YouTube Focus in general_settings_view.dart',
      );

      final nodeScript = r'''
const assert = require("assert");
const path = require("path");
const core = require(path.resolve("chronos_extension/focus_filters_core.js"));
const hudPanel = require(path.resolve("chronos_extension/focus_hud_panel.js"));

assert.strictEqual(hudPanel.FILTER_GROUPS[0].title, "DETOX GLOBAL");
assert.strictEqual(hudPanel.FILTER_GROUPS[1].title, "YOUTUBE");

global.ChronosFocusCore = core;
global.CSSStyleSheet = class {
  replaceSync(text) { this.text = text; }
};

function makeStorage() {
  const m = new Map();
  return {
    getItem(k) { return m.has(k) ? m.get(k) : null; },
    setItem(k, v) { m.set(k, String(v)); },
    removeItem(k) { m.delete(k); },
    dump() { return m; }
  };
}
global.sessionStorage = makeStorage();
global.localStorage = makeStorage();

function makeNode(tag) {
  const listeners = {};
  const attrs = {};
  let _text = "";
  const node = {
    tagName: tag.toUpperCase(),
    children: [],
    parentNode: null,
    isConnected: false,
    className: "",
    get textContent() { return _text; },
    set textContent(v) {
      _text = v === undefined || v === null ? "" : String(v);
      if (_text === "") node.children.length = 0;
    },
    checked: false,
    value: "",
    type: "",
    id: "",
    title: "",
    style: {},
    classList: {
      add(cls) {
        const set = new Set((node.className || "").split(/\s+/).filter(Boolean));
        set.add(cls);
        node.className = Array.from(set).join(" ");
      },
      remove(cls) {
        const set = new Set((node.className || "").split(/\s+/).filter(Boolean));
        set.delete(cls);
        node.className = Array.from(set).join(" ");
      },
      toggle(cls, force) {
        const set = new Set((node.className || "").split(/\s+/).filter(Boolean));
        const next = typeof force === "boolean" ? force : !set.has(cls);
        if (next) set.add(cls); else set.delete(cls);
        node.className = Array.from(set).join(" ");
        return next;
      },
      contains(cls) {
        return (node.className || "").split(/\s+/).includes(cls);
      }
    },
    get firstElementChild() { return node.children[0] || null; },
    getBoundingClientRect() {
      const host = node.parentNode && node.parentNode._host ? node.parentNode._host : node;
      const st = host.style || node.style || {};
      const eyeSz = parseFloat((node.style && node.style.height) || "") || 32;
      const pillH = parseFloat((node.style && node.style.minHeight) || "") || 32;
      const w = node.classList.contains("c-eye") ? eyeSz : 140;
      const h = node.classList.contains("c-eye") ? eyeSz : pillH;
      const left = st.left && st.left.endsWith("px")
        ? parseFloat(st.left)
        : (st.right && st.right.endsWith("px") ? 1024 - parseFloat(st.right) - w : 1024 - 18 - w);
      const top = st.top && st.top.endsWith("px")
        ? parseFloat(st.top)
        : (st.bottom && st.bottom.endsWith("px") ? 768 - parseFloat(st.bottom) - h : 768 - 18 - h);
      return { left, top, right: left + w, bottom: top + h, width: w, height: h };
    },
    setAttribute(k, v) { attrs[k] = String(v); },
    getAttribute(k) { return attrs[k]; },
    appendChild(child) {
      child.parentNode = node;
      child.isConnected = true;
      node.children.push(child);
      return child;
    },
    removeChild(child) {
      node.children = node.children.filter((c) => c !== child);
      child.parentNode = null;
      child.isConnected = false;
    },
    addEventListener(type, fn) {
      listeners[type] = listeners[type] || [];
      listeners[type].push(fn);
    },
    removeEventListener(type, fn) {
      listeners[type] = (listeners[type] || []).filter((f) => f !== fn);
    },
    dispatch(type, ev) {
      (listeners[type] || []).forEach((fn) => fn(ev || { stopPropagation() {} }));
    },
    attachShadow() {
      const root = makeNode("#shadow");
      root.adoptedStyleSheets = [];
      root._host = node;
      node.shadowRoot = root;
      return root;
    },
    contains(other) {
      if (other === node) return true;
      return node.children.some((c) => c.contains(other));
    }
  };
  return node;
}

const winListeners = {};
const docListeners = {};
const body = makeNode("body");
let proxyEl = null;
global.window = {
  innerWidth: 1024,
  innerHeight: 768,
  location: { hostname: "www.youtube.com" },
  addEventListener(type, fn) {
    winListeners[type] = winListeners[type] || [];
    winListeners[type].push(fn);
  },
  removeEventListener(type, fn) {
    winListeners[type] = (winListeners[type] || []).filter((f) => f !== fn);
  },
  dispatch(type, ev) {
    (winListeners[type] || []).forEach((fn) => fn(ev));
  }
};
global.window.top = global.window;
global.window.self = global.window;
global.document = {
  body,
  documentElement: makeNode("html"),
  hidden: false,
  createElement: (t) => makeNode(t),
  createElementNS: (_ns, t) => makeNode(t),
  addEventListener(type, fn) {
    docListeners[type] = docListeners[type] || [];
    docListeners[type].push(fn);
  },
  removeEventListener(type, fn) {
    docListeners[type] = (docListeners[type] || []).filter((f) => f !== fn);
  },
  querySelector: (sel) => (sel.includes('data-chronos-proxy="1"') ? proxyEl : null),
};

let savedCalls = [];
let appliedCalls = [];
let persistedPositions = [];
let nowOffset = 0;
const realNow = Date.now;
Date.now = () => realNow() + nowOffset;

let antiCheatResp = false;
let rejectNextSaveWithAc = false;
const hud = hudPanel.create({
  source: "extension",
  getHost: () => "www.youtube.com",
  getInitialFilters: () => ({
    ytBlockShorts: true,
    ytEducationalMode: false,
    hudAlpha: 0.94,
    hudScale: 1.0,
    hudHideToEye: true,
    launcherFilterEnabled: true,
    launcherBlockedTags: ["NSFW"],
    launcherBlockedNames: [],
  }),
  onApplyFilters: (f) => appliedCalls.push(f),
  onSaveFilters: (f, done) => {
    if (rejectNextSaveWithAc) {
      rejectNextSaveWithAc = false;
      done({
        success: false,
        antiCheatLocked: true,
        antiCheatActive: true,
        message: "Anti-Burla ativo",
        filters: {
          ytBlockShorts: true,
          ytEducationalMode: true,
          globalGrayscale: true,
          hudAlpha: 0.4,
          hudScale: 1.5,
          hudHideToEye: true,
          launcherFilterEnabled: true,
          launcherBlockedTags: ["NSFW", "Soulslike"],
          launcherBlockedNames: [],
        },
      });
      return;
    }
    savedCalls.push(f);
    done({ success: true, filters: f, antiCheatActive: antiCheatResp });
  },
  onRequestStatus: (done) => {
    done({
      isConnected: true,
      antiCheatActive: antiCheatResp,
      focusFilters: {
        ytBlockShorts: true,
        ytEducationalMode: false,
        globalGrayscale: true,
        hudAlpha: 0.94,
        hudScale: 1.0,
        hudHideToEye: true,
        launcherFilterEnabled: true,
        launcherBlockedTags: ["NSFW"],
        launcherBlockedNames: [],
      },
      sites: [
        {
          entityId: "youtube.com",
          displayName: "YouTube",
          pattern: "youtube.com",
          remainingSeconds: 600,
          dailyQuotaSeconds: 1200,
          consumedSeconds: 600,
          emergencyTokensRemaining: 2,
          isBlocked: false,
        },
      ],
    });
  },
  savePosition: (pos) => persistedPositions.push(pos),
});

function findByClass(root, cls) {
  for (const c of root.children || []) {
    if (c.classList && c.classList.contains(cls)) return c;
    const nested = findByClass(c, cls);
    if (nested) return nested;
  }
  return null;
}

function findByAttr(root, attr, val) {
  for (const c of root.children || []) {
    if (c.getAttribute && c.getAttribute(attr) === val) return c;
    const nested = findByAttr(c, attr, val);
    if (nested) return nested;
  }
  return null;
}

function collectByTag(root, tag) {
  const out = [];
  for (const c of root.children || []) {
    if (c.tagName === tag) out.push(c);
    out.push(...collectByTag(c, tag));
  }
  return out;
}

function collectText(root) {
  let txt = root.textContent || "";
  for (const c of root.children || []) {
    txt += " " + collectText(c);
  }
  return txt;
}

assert.strictEqual(hud.ensureMounted(), true);
const hostNode = body.children.find((c) => c.id === "chronos-focus-hud");
assert.ok(hostNode, "HUD host should be appended to body");
assert.strictEqual(hostNode.getAttribute("data-chronos-extension"), "1");
assert.strictEqual(hostNode.shadowRoot.adoptedStyleSheets.length, 1, "Extension HUD should use Constructable Stylesheets without inline style tag");

const pillWrap = findByClass(hostNode.shadowRoot, "c-pill");
const pillMain = findByClass(pillWrap, "c-pill-main");
const pillHideBtn = findByClass(pillWrap, "c-pill-hide");
const eyeBtn = findByClass(hostNode.shadowRoot, "c-eye");
const eyeDot = findByClass(eyeBtn, "c-eye-dot");
const panelEl = findByClass(hostNode.shadowRoot, "c-panel");
const toastEl = findByClass(hostNode.shadowRoot, "c-toast");

// Minimal pill design: NO 6-dot grip and NO "Filtros" / gear text
assert.strictEqual(findByClass(pillWrap, "c-grip"), null, "6-dot grip must be removed");
assert.strictEqual(findByClass(pillWrap, "c-gear"), null, "Gear icon must be removed");
const pillText = collectText(pillWrap);
assert.strictEqual(pillText.includes("Filtros"), false, "Pill must not show 'Filtros' label");
assert.strictEqual(pillText.includes("\u2699"), false, "Pill must not show gear character");
assert.strictEqual(pillWrap.style.opacity, "0.94");
assert.strictEqual(eyeBtn.style.opacity, "0.94");
assert.strictEqual(eyeBtn.classList.contains("is-hidden"), true, "Eye button starts hidden while pill is visible");

// 1. Dragging directly on .c-pill moves & anchors top-left cleanly without opening panel
pillWrap.dispatch("pointerdown", { button: 0, pointerId: 1, clientX: 900, clientY: 730, target: pillMain });
global.window.dispatch("pointermove", { pointerId: 1, clientX: 50, clientY: 60 });
assert.strictEqual(pillWrap.classList.contains("is-dragging"), true);
global.window.dispatch("pointerup", { pointerId: 1, clientX: 50, clientY: 60 });
assert.strictEqual(pillWrap.classList.contains("is-dragging"), false);
assert.strictEqual(hud.isPanelOpen(), false, "Drag release must not toggle panel open");
const savedPos = hud.getPosition();
assert.ok(savedPos && savedPos.anchorX === "left" && savedPos.anchorY === "top", "Dragged corner should anchor top-left");
assert.strictEqual(hostNode.style.left, savedPos.offsetX + "px");
assert.strictEqual(hostNode.style.top, savedPos.offsetY + "px");
assert.strictEqual(persistedPositions.length, 1);

// 2. Clicking Hide button with hudHideToEye=true collapses pill into draggable Eye at same position
pillHideBtn.dispatch("click", { stopPropagation() {} });
assert.strictEqual(hud.getViewMode(), "eye");
assert.strictEqual(hud.isHidden(), true);
assert.strictEqual(pillWrap.classList.contains("is-hidden"), true);
assert.strictEqual(eyeBtn.classList.contains("is-hidden"), false);
assert.strictEqual(toastEl.classList.contains("is-hidden"), true, "Collapsing into draggable Eye should not show full-hide toast");

// 3. Dragging the Eye moves it to bottom-right and keeps viewMode === "eye"
eyeBtn.dispatch("pointerdown", { button: 0, pointerId: 2, clientX: 14, clientY: 14, target: eyeBtn });
global.window.dispatch("pointermove", { pointerId: 2, clientX: 990, clientY: 740 });
assert.strictEqual(eyeBtn.classList.contains("is-dragging"), true);
global.window.dispatch("pointerup", { pointerId: 2, clientX: 990, clientY: 740 });
assert.strictEqual(eyeBtn.classList.contains("is-dragging"), false);
assert.strictEqual(hud.getViewMode(), "eye", "Dragging Eye must not prematurely expand pill");
const eyePos = hud.getPosition();
assert.ok(eyePos && eyePos.anchorX === "right" && eyePos.anchorY === "bottom", "Dragged Eye should anchor bottom-right");
assert.strictEqual(persistedPositions.length, 2);

// 4. Clicking the Eye (<5px after drag cooldown) restores the Pill
nowOffset += 500;
eyeBtn.dispatch("click", { stopPropagation() {}, preventDefault() {} });
assert.strictEqual(hud.getViewMode(), "pill");
assert.strictEqual(hud.isHidden(), false);
assert.strictEqual(pillWrap.classList.contains("is-hidden"), false);
assert.strictEqual(eyeBtn.classList.contains("is-hidden"), true);

// 5. Alt+Shift+C hides completely (full hide + toast) and restores on second press
global.window.dispatch("keydown", { altKey: true, shiftKey: true, ctrlKey: false, metaKey: false, code: "KeyC", key: "c", preventDefault() {} });
assert.strictEqual(hud.getViewMode(), "hidden");
assert.strictEqual(hud.isHidden(), true, "Alt+Shift+C should completely hide HUD");
assert.strictEqual(pillWrap.classList.contains("is-hidden"), true);
assert.strictEqual(eyeBtn.classList.contains("is-hidden"), true);
assert.strictEqual(toastEl.classList.contains("is-hidden"), false, "Toast hint should display on full hide");

global.window.dispatch("keydown", { altKey: true, shiftKey: true, ctrlKey: false, metaKey: false, code: "KeyC", key: "c", preventDefault() {} });
assert.strictEqual(hud.getViewMode(), "pill");
assert.strictEqual(hud.isHidden(), false, "Alt+Shift+C should restore pill");
assert.strictEqual(pillWrap.classList.contains("is-hidden"), false);

// 6. Clicking pill opens App-Miniature panel cleanly
nowOffset += 500;
pillMain.dispatch("click", { stopPropagation() {}, preventDefault() {} });
assert.strictEqual(hud.isPanelOpen(), true);
assert.strictEqual(panelEl.classList.contains("is-open"), true);

hud.updateRule({
  entityId: "youtube.com",
  displayName: "YouTube",
  remainingSeconds: 125,
  dailyQuotaSeconds: 600,
  consumedSeconds: 475,
  emergencyTokensRemaining: 2,
});
assert.ok(pillMain.children[1].textContent.includes("YouTube: 02:05"));
assert.strictEqual(pillMain.children[0].className, "c-dot is-danger");
assert.strictEqual(eyeDot.className, "c-eye-dot is-danger");
assert.strictEqual(findByClass(panelEl, "c-hero-clock").textContent, "00:02:05");
assert.strictEqual(findByClass(panelEl, "c-tokens-pill").textContent, "Tokens: 2/2");
const sitesContainer = findByClass(panelEl, "c-sites");
assert.ok(findByClass(sitesContainer, "c-site-row"), "Active session list should render monitored sites");

// Miniature App tabs switch between Tempo and Filtros views
const navTempoBtn = findByAttr(panelEl, "data-nav-tab", "tempo");
const navFiltersBtn = findByAttr(panelEl, "data-nav-tab", "filtros");
const viewWraps = panelEl.children.filter((c) => c.classList && c.classList.contains("c-view-wrap"));
assert.strictEqual(viewWraps.length, 2);
assert.strictEqual(viewWraps[0].classList.contains("is-hidden"), false);
assert.strictEqual(viewWraps[1].classList.contains("is-hidden"), true);
navFiltersBtn.dispatch("click", {});
assert.strictEqual(viewWraps[0].classList.contains("is-hidden"), true);
assert.strictEqual(viewWraps[1].classList.contains("is-hidden"), false);
navTempoBtn.dispatch("click", {});
assert.strictEqual(viewWraps[0].classList.contains("is-hidden"), false);
assert.strictEqual(viewWraps[1].classList.contains("is-hidden"), true);

// 7. Closed eye icon + circular diameter matching pill height + Filter/HUD controls
assert.ok(eyeBtn.firstElementChild && eyeBtn.firstElementChild.tagName === "SVG", "Eye button must contain SVG");
assert.ok(
  eyeBtn.firstElementChild.children.some((c) => c.tagName === "LINE"),
  "Eye button must render closed/crossed eye SVG"
);
assert.strictEqual(eyeBtn.style.borderRadius, "50%");
assert.strictEqual(eyeBtn.style.width, eyeBtn.style.height);

const inputs = collectByTag(hostNode.shadowRoot, "INPUT");
assert.strictEqual(
  inputs.length,
  23,
  "Expected 17 focus toggles + hudAlpha + hudScale + hudHideToEye + launcherEnabled + 2 launcher term inputs"
);

const alphaInput = inputs.find((i) => i.getAttribute("data-filter-key") === "hudAlpha");
alphaInput.value = "40";
alphaInput.dispatch("input", {});
assert.strictEqual(pillWrap.style.opacity, "0.4");
assert.strictEqual(eyeBtn.style.opacity, "0.4");
alphaInput.dispatch("change", {});
assert.strictEqual(savedCalls.length, 1);
assert.strictEqual(savedCalls[0].hudAlpha, 0.4);

const scaleInput = inputs.find((i) => i.getAttribute("data-filter-key") === "hudScale");
scaleInput.value = "150";
scaleInput.dispatch("input", {});
assert.strictEqual(pillWrap.style.minHeight, "48px");
assert.strictEqual(pillWrap.style.fontSize, "18.0px");
assert.strictEqual(eyeBtn.style.width, "48px", "Eye diameter must scale with pill height");
assert.strictEqual(eyeBtn.style.height, "48px", "Eye height must equal pill height");
scaleInput.dispatch("change", {});
assert.strictEqual(savedCalls.length, 2);
assert.strictEqual(savedCalls[1].hudScale, 1.5);

const eduInput = inputs.find((i) => i.getAttribute("data-filter-key") === "ytEducationalMode");
eduInput.checked = true;
eduInput.dispatch("change", {});
assert.strictEqual(savedCalls.length, 3);
assert.strictEqual(savedCalls[2].ytEducationalMode, true);
assert.ok(appliedCalls.length >= 1);

// Adding launcher tag works anytime, while Anti-Burla blocks removal or disabling
const tagInput = inputs.find((i) => i.getAttribute("data-launcher-input") === "tags");
tagInput.value = "Soulslike";
tagInput.dispatch("keydown", { key: "Enter", preventDefault() {} });
assert.strictEqual(savedCalls.length, 4);
assert.deepStrictEqual(savedCalls[3].launcherBlockedTags, ["NSFW", "Soulslike"]);

// Simulate backend HTTP 403 antiCheatLocked rejection reverting filter state
rejectNextSaveWithAc = true;
const launcherChk = inputs.find((i) => i.getAttribute("data-filter-key") === "launcherFilterEnabled");
launcherChk.checked = false;
launcherChk.dispatch("change", {});
assert.strictEqual(launcherChk.checked, true, "Anti-Burla lock must revert launcher toggle back to enabled");
const lockBanner = findByClass(panelEl, "c-ac-lock");
assert.ok(lockBanner && !lockBanner.classList.contains("is-hidden"), "Anti-Burla banner must become visible when locked");

// Turning hudHideToEye off causes Hide button to hide completely instead of Eye
const hideToEyeInput = inputs.find((i) => i.getAttribute("data-filter-key") === "hudHideToEye");
hideToEyeInput.checked = false;
hideToEyeInput.dispatch("change", {});
assert.strictEqual(savedCalls[4].hudHideToEye, false);
pillHideBtn.dispatch("click", { stopPropagation() {} });
assert.strictEqual(hud.getViewMode(), "hidden");
assert.strictEqual(eyeBtn.classList.contains("is-hidden"), true);
hud.setHidden(false);
assert.strictEqual(hud.getViewMode(), "pill");

// When proxy HUD appears, extension yields and removes its own node
proxyEl = makeNode("div");
proxyEl.setAttribute("data-chronos-proxy", "1");
assert.strictEqual(hud.ensureMounted(), false);
assert.strictEqual(body.children.includes(hostNode), false);
proxyEl = null;

// Skip mounting in iframes
global.window.self = {};
assert.strictEqual(hud.ensureMounted(), false);
console.log("HUD_PANEL_OK");
''';

      final nodeRes = await Process.run('node', ['-e', nodeScript]);
      expect(nodeRes.exitCode, equals(0), reason: 'stderr: ${nodeRes.stderr}');
      expect(nodeRes.stdout.toString(), contains('HUD_PANEL_OK'));
    });

    test('ChronosLauncherDomFilter blocks single-game/guide/discussion/artwork pages and hides store cards', () async {
      final launcherScript = r'''
const assert = require("assert");
const path = require("path");
require(path.resolve("chronos_extension/focus_filters_core.js"));

const launcherFilter = global.ChronosLauncherDomFilter;
assert.ok(launcherFilter && typeof launcherFilter.apply === "function");

function makeEl(opts) {
  const attrs = Object.assign({}, (opts && opts.attrs) || {});
  const el = {
    textContent: (opts && opts.textContent) || "",
    style: {
      setProperty(k, v) { el.style[k] = v; },
      removeProperty(k) { delete el.style[k]; },
    },
    parentElement: (opts && opts.parentElement) || null,
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
    setAttribute(k, v) { attrs[k] = String(v); },
    removeAttribute(k) { delete attrs[k]; },
    closest(sel) {
      let cur = el;
      while (cur) {
        if (cur._matches && cur._matches.some((s) => sel.includes(s))) return cur;
        cur = cur.parentElement;
      }
      return null;
    },
    querySelectorAll() { return []; },
    querySelector() { return null; },
    _matches: (opts && opts.matches) || [],
  };
  return el;
}

const filters = {
  launcherFilterEnabled: true,
  launcherBlockedTags: ["Soulslike", "NSFW"],
  launcherBlockedNames: ["Elden Ring"],
};

// 1. Direct single-game page matching blocked name -> full page block without needing remote lookup
let blockedCalls = [];
const pageDoc1 = {
  title: "Save 30% on Elden Ring on Steam",
  querySelectorAll: () => [],
  querySelector: (sel) => (sel.includes("apphub_AppName") ? makeEl({ textContent: "Elden Ring" }) : null),
};
launcherFilter.apply(filters, {
  document: pageDoc1,
  url: "https://store.steampowered.com/app/1245620/ELDEN_RING/",
  host: "store.steampowered.com",
  resolveItems: () => { throw new Error("Should block locally before async resolve"); },
  onBlockPage: (info) => blockedCalls.push(info),
});
assert.strictEqual(blockedCalls.length, 1);
assert.strictEqual(blockedCalls[0].appId, 1245620);

// 2. Steam guide / discussion / artwork page linked via breadcrumb /app/<id>/ -> resolved via API tags -> full block
blockedCalls = [];
const breadcrumbAppLink = makeEl({ attrs: { href: "https://store.steampowered.com/app/570/Dota_2/" } });
const guideTitleEl = makeEl({ textContent: "Hero Build Guide - Artwork & Tips" });
const pageDoc2 = {
  title: "Steam Community :: Guide :: Hero Build Guide",
  querySelectorAll(sel) {
    if (sel.includes("/app/")) return [breadcrumbAppLink];
    return [];
  },
  querySelector(sel) {
    if (sel.includes("apphub_AppName")) return makeEl({ textContent: "Dota 2" });
    if (sel.includes("workshopItemTitle")) return guideTitleEl;
    return null;
  },
};
launcherFilter.apply(filters, {
  document: pageDoc2,
  url: "https://steamcommunity.com/sharedfiles/filedetails/?id=999888",
  host: "steamcommunity.com",
  resolveItems: (items, done) => {
    const pageItem = items.find((i) => i.appId === 570);
    assert.ok(pageItem, "Guide/Artwork page should extract breadcrumb appId 570");
    done({
      results: [{ id: pageItem.id, title: "Dota 2", tags: ["MOBA", "Soulslike"], blocked: true, reason: "Tag bloqueada: Soulslike" }],
    });
  },
  onBlockPage: (info) => blockedCalls.push(info),
});
assert.strictEqual(blockedCalls.length, 1);
assert.ok(blockedCalls[0].reason.includes("Soulslike"));

// 3. Storefront feed hides blocked game cards while keeping allowed ones visible, and restores when disabled
const blockedCard = makeEl({ attrs: { "data-ds-appid": "730" }, matches: ["[data-ds-appid]"] });
blockedCard.querySelector = () => makeEl({ textContent: "Counter-Strike" });
const allowedCard = makeEl({ attrs: { "data-ds-appid": "440" }, matches: ["[data-ds-appid]"] });
allowedCard.querySelector = () => makeEl({ textContent: "Team Fortress 2" });

let hiddenNodes = [blockedCard];
const feedDoc = {
  title: "Steam Store",
  querySelectorAll(sel) {
    if (sel.includes("data-chronos-launcher-hidden")) {
      return hiddenNodes.filter((n) => n.getAttribute("data-chronos-launcher-hidden") === "1");
    }
    if (sel.includes("data-ds-appid")) return [blockedCard, allowedCard];
    return [];
  },
  querySelector: () => null,
};

let feedBlocked = 0;
launcherFilter.apply(filters, {
  document: feedDoc,
  url: "https://store.steampowered.com/",
  host: "store.steampowered.com",
  resolveItems: (items, done) => {
    done({
      results: items.map((it) => ({
        id: it.id,
        blocked: it.appId === 730,
        reason: it.appId === 730 ? "Tag bloqueada: NSFW" : "",
      })),
    });
  },
  onBlockPage: () => { feedBlocked += 1; },
});
assert.strictEqual(feedBlocked, 0, "Storefront feed must hide matching cards instead of blocking entire home page");
assert.strictEqual(blockedCard.style.display, "none");
assert.strictEqual(blockedCard.getAttribute("data-chronos-launcher-hidden"), "1");
assert.notStrictEqual(allowedCard.style.display, "none");

launcherFilter.apply(Object.assign({}, filters, { launcherFilterEnabled: false }), {
  document: feedDoc,
  url: "https://store.steampowered.com/",
  host: "store.steampowered.com",
});
assert.strictEqual(blockedCard.getAttribute("data-chronos-launcher-hidden"), null);

// 4. Tag hubs (/tags/en/Hentai/), search tag query (/search/?tags=9130), and logged-out login redir (?redir=app%2F339800)
assert.strictEqual(
  launcherFilter.extractSteamAppIdFromUrl("https://store.steampowered.com/login/?redir=app%2F339800%2FHuniePop%2F&snr=1"),
  339800
);
let tagHubBlocked = 0;
launcherFilter.apply({ launcherFilterEnabled: true, launcherBlockedTags: ["NSFW"], launcherBlockedNames: [] }, {
  document: { title: "Hentai", querySelectorAll: () => [], querySelector: () => null },
  url: "https://store.steampowered.com/tags/en/Hentai/",
  host: "store.steampowered.com",
  resolveItems: () => { throw new Error("Tag hub should block locally"); },
  onBlockPage: () => { tagHubBlocked += 1; },
});
assert.strictEqual(tagHubBlocked, 1, "Tag hub /tags/en/Hentai/ must be blocked when NSFW is blocked");

let qsTagBlocked = 0;
launcherFilter.apply({ launcherFilterEnabled: true, launcherBlockedTags: ["Conteúdo Adulto"], launcherBlockedNames: [] }, {
  document: { title: "Steam Search", querySelectorAll: () => [], querySelector: () => null },
  url: "https://store.steampowered.com/search/?tags=9130",
  host: "store.steampowered.com",
  resolveItems: () => { throw new Error("Numeric search tag=9130 should block locally"); },
  onBlockPage: () => { qsTagBlocked += 1; },
});
assert.strictEqual(qsTagBlocked, 1, "Search ?tags=9130 must be blocked when Conteúdo Adulto is blocked");

// 5. Instant 0ms local hiding from data-ds-tagids & data-ds-descids + Steam React <a href="/app/..."> cards + >60 batch continuation
const instantTagCard = makeEl({
  attrs: { "data-ds-appid": "999001", "data-ds-tagids": "[9130, 19]", "data-ds-descids": "[1, 3]" },
  matches: ["[data-ds-appid]"],
});
const manyCards = [instantTagCard];
for (let idx = 1; idx <= 65; idx++) {
  const c = makeEl({
    attrs: { "data-ds-appid": String(10000 + idx) },
    matches: ["[data-ds-appid]"],
  });
  c.querySelector = () => makeEl({ textContent: "Game " + idx });
  manyCards.push(c);
}
const manyDoc = {
  title: "Welcome to Steam",
  querySelectorAll(sel) {
    if (sel === "[data-ds-appid]") return manyCards;
    return [];
  },
  querySelector: () => null,
};
const resolvedBatches = [];
launcherFilter.apply({ launcherFilterEnabled: true, launcherBlockedTags: ["NSFW"], launcherBlockedNames: [] }, {
  document: manyDoc,
  url: "https://store.steampowered.com/",
  host: "store.steampowered.com",
  resolveItems: (items, done) => {
    resolvedBatches.push(items.map((i) => i.appId));
    done({
      results: items.map((i) => ({
        id: i.id,
        appId: i.appId,
        blocked: i.appId === 10065,
        reason: i.appId === 10065 ? "Tag bloqueada: NSFW" : "",
      })),
    });
  },
  onBlockPage: () => { throw new Error("Home page must not block as whole page"); },
});
assert.strictEqual(instantTagCard.style.display, "none", "Card with data-ds-tagids [9130] & descids [3] must hide immediately");
assert.strictEqual(resolvedBatches.length, 1);
assert.strictEqual(resolvedBatches[0].length, 60, "First batch should resolve 60 cards");

setTimeout(() => {
  assert.ok(resolvedBatches.length >= 2, "Remaining cards 61..65 must be scheduled automatically after batch 1");
  assert.strictEqual(manyCards[manyCards.length - 1].style.display, "none", "Card #65 after batch cap must also be hidden");
  console.log("LAUNCHER_DOM_OK");
}, 120);
''';

      final nodeRes = await Process.run('node', ['-e', launcherScript]);
      expect(nodeRes.exitCode, equals(0), reason: 'stderr: ${nodeRes.stderr}');
      expect(nodeRes.stdout.toString(), contains('LAUNCHER_DOM_OK'));
    });

    test('ChronosYoutubeTypeFilter reveals only allowed home/related cards and skips disallowed Shorts', () async {
      final ytScript = r'''
const assert = require("assert");
const path = require("path");
const core = require(path.resolve("chronos_extension/focus_filters_core.js"));

function card(videoId) {
  const attrs = {};
  const link = { getAttribute: (k) => (k === "href" ? "/watch?v=" + videoId + "&pp=x" : null) };
  return {
    getAttribute: (k) => (k in attrs ? attrs[k] : null),
    setAttribute: (k, v) => { attrs[k] = String(v); },
    removeAttribute: (k) => { delete attrs[k]; },
    querySelector: () => link,
  };
}
const eduCard = card("EduVid12345");
const funCard = card("FunVid12345");
const doc = { querySelectorAll: () => [eduCard, funCard] };
const filters = { ytShowOnlyEnabled: true, ytShowOnlyTypes: ["educacional"], ytBlockShorts: false };

// CSS hides unmarked cards on home; disabled filter adds nothing
const css = core.buildFocusCss(core.normalizeFilters(filters), "www.youtube.com", "/");
assert.ok(css.includes('ytd-rich-item-renderer:not([data-chronos-yt-ok="1"])'));
assert.ok(!core.buildFocusCss(core.normalizeFilters({ ytShowOnlyEnabled: true, ytShowOnlyTypes: [] }), "www.youtube.com", "/").includes("data-chronos-yt-ok"),
  "show-only with empty list is never enabled");

const f = core.createYoutubeTypeFilter();
let requests = 0;
const classifyItems = (items, done) => {
  requests += 1;
  done({ results: items.map((it) => ({ id: it.id, known: true, types: it.videoId === "EduVid12345" ? ["educacional"] : ["entretenimento"] })) });
};
let skips = 0;
f.apply(filters, { document: doc, location: { hostname: "www.youtube.com", pathname: "/" }, classifyItems, skipShort: () => skips++ });
assert.strictEqual(eduCard.getAttribute("data-chronos-yt-ok"), "1");
assert.strictEqual(funCard.getAttribute("data-chronos-yt-ok"), null);
assert.strictEqual(requests, 1, "one batch for unknown cards");
f.apply(filters, { document: doc, location: { hostname: "www.youtube.com", pathname: "/" }, classifyItems, skipShort: () => skips++ });
assert.strictEqual(requests, 1, "cached results are reused");

// Shorts: disallowed is skipped once, allowed is not
const emptyDoc = { querySelectorAll: () => [] };
f.apply(filters, { document: emptyDoc, location: { hostname: "www.youtube.com", pathname: "/shorts/FunVid12345" }, classifyItems, skipShort: () => skips++ });
assert.strictEqual(skips, 1);
f.apply(filters, { document: emptyDoc, location: { hostname: "www.youtube.com", pathname: "/shorts/FunVid12345" }, classifyItems, skipShort: () => skips++ });
assert.strictEqual(skips, 1, "same short is not skipped twice");
f.apply(filters, { document: emptyDoc, location: { hostname: "www.youtube.com", pathname: "/shorts/EduVid12345" }, classifyItems, skipShort: () => skips++ });
assert.strictEqual(skips, 1, "allowed short plays");

// Off-YouTube or disabled: no-op
const other = card("FunVid12345");
f.apply({ ytShowOnlyEnabled: false, ytShowOnlyTypes: ["educacional"] }, { document: { querySelectorAll: () => [other] }, location: { hostname: "www.youtube.com", pathname: "/" }, classifyItems });
assert.strictEqual(other.getAttribute("data-chronos-yt-ok"), null);
console.log("YT_TYPE_FILTER_OK");
''';
      final nodeRes = await Process.run('node', ['-e', ytScript]);
      expect(nodeRes.exitCode, equals(0), reason: 'stderr: ${nodeRes.stderr}\nstdout: ${nodeRes.stdout}');
      expect(nodeRes.stdout.toString(), contains('YT_TYPE_FILTER_OK'));
    });

    test('ChronosLauncherDomFilter hides lutris.net search cards (.game-preview) and ignores listing links', () async {
      final lutrisScript = r'''
const assert = require("assert");
const path = require("path");
require(path.resolve("chronos_extension/focus_filters_core.js"));
const launcherFilter = global.ChronosLauncherDomFilter;

function el(tagName, opts) {
  const o = opts || {};
  const attrs = Object.assign({}, o.attrs || {});
  const node = {
    tagName,
    textContent: o.text || "",
    classes: o.classes || [],
    children: [],
    parentElement: null,
    style: {
      setProperty(k, v) { node.style[k] = v; },
      removeProperty(k) { delete node.style[k]; },
    },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
    setAttribute(k, v) { attrs[k] = String(v); },
    removeAttribute(k) { delete attrs[k]; },
    matches(sel) { return sel.split(",").some((s) => simpleMatch(node, s.trim())); },
    closest(sel) {
      let cur = node;
      while (cur) {
        if (cur.matches && cur.matches(sel)) return cur;
        cur = cur.parentElement;
      }
      return null;
    },
    querySelectorAll(sel) { return descendants(node).filter((d) => d.matches(sel)); },
    querySelector(sel) { return node.querySelectorAll(sel)[0] || null; },
  };
  for (const c of o.children || []) { c.parentElement = node; node.children.push(c); }
  return node;
}
function descendants(n) { return n.children.flatMap((c) => [c, ...descendants(c)]); }
function simpleMatch(node, s) {
  if (s.startsWith(".")) return node.classes.includes(s.slice(1).split(/[\s\[]/)[0]) && !s.includes(" ");
  const m = s.match(/^a\[href\*=["']([^"']+)["']\]$/);
  if (m) return node.tagName === "A" && String(node.getAttribute("href") || "").includes(m[1]);
  if (s === "a[href]") return node.tagName === "A" && node.getAttribute("href") != null;
  if (/^(header|nav|footer)$/.test(s)) return node.tagName.toLowerCase() === s;
  return false;
}
function preview(slug, name, extra) {
  return el("DIV", {
    classes: ["game-preview"],
    children: [
      el("A", { attrs: { href: `/games/${slug}/`, title: name } }),
      el("DIV", {
        classes: ["game-details"],
        children: [
          el("A", { classes: ["game-name"], attrs: { href: `/games/${slug}/` }, text: name }),
          el("SPAN", { classes: ["small-text"], children: extra || [] }),
        ],
      }),
    ],
  });
}

const isaac = preview("the-binding-of-isaac-rebirth", "The Binding of Isaac: Rebirth");
const asimov = preview("isaac-asimovs-the-ultimate-robot", "Isaac Asimov's The Ultimate Robot", [
  el("A", { attrs: { href: "/games/year/1994" }, text: "1994" }),
]);
const navLink = el("A", { attrs: { href: "/games/platform/1" }, text: "Windows" });
const root = el("BODY", { children: [isaac, asimov, navLink] });
const doc = { title: "Games - Lutris", querySelectorAll: (s) => root.querySelectorAll(s), querySelector: (s) => root.querySelector(s) };

const sent = [];
let pageBlocks = 0;
launcherFilter.apply(
  { launcherFilterEnabled: true, launcherBlockedTags: ["Roguelike"], launcherBlockedNames: [] },
  {
    document: doc,
    url: "https://lutris.net/games/?q=isaac",
    host: "lutris.net",
    resolveItems: (items, done) => {
      sent.push(...items);
      done({
        success: true,
        results: items.map((it) => ({
          id: it.id,
          blocked: /binding of isaac/i.test(it.title),
          reason: "Bloqueado pela tag \"Roguelike\" (Steam API)",
        })),
      });
    },
    onBlockPage: () => { pageBlocks += 1; },
  }
);
setTimeout(() => {
  const titles = sent.map((i) => i.title);
  assert.ok(titles.includes("The Binding of Isaac: Rebirth"), "Isaac card sent: " + JSON.stringify(titles));
  assert.ok(!titles.some((t) => /^(1994|year|windows|platform)$/i.test(t)), "listing links must not become cards: " + JSON.stringify(titles));
  assert.strictEqual(pageBlocks, 0, "search page must not be blocked as a whole");
  assert.strictEqual(isaac.getAttribute("data-chronos-launcher-hidden"), "1");
  assert.strictEqual(asimov.getAttribute("data-chronos-launcher-hidden"), null);
  console.log("LUTRIS_CARDS_OK");
}, 400);
''';
      final nodeRes = await Process.run('node', ['-e', lutrisScript]);
      expect(nodeRes.exitCode, equals(0), reason: 'stderr: ${nodeRes.stderr}\nstdout: ${nodeRes.stdout}');
      expect(nodeRes.stdout.toString(), contains('LUTRIS_CARDS_OK'));
    });

    test('Extension popup tab separation, site dropdown rendering, autocomplete, SSE push, and Firefox sync', () async {
      // 1. Verify shared extension files match identically between Chrome & Firefox builds
      for (final sharedFile in <String>[
        'focus_filters_core.js',
        'focus_hud_panel.js',
        'content.js',
        'popup.html',
        'popup.js',
      ]) {
        final chromeBytes = File('chronos_extension/$sharedFile').readAsBytesSync();
        final firefoxBytes = File('chronos_extension_firefox/$sharedFile').readAsBytesSync();
        expect(firefoxBytes, equals(chromeBytes), reason: '$sharedFile out of sync in chronos_extension_firefox');
      }

      // 2. Verify popup.html separates Filters vs Sites/Sessions tabs without raw JSON fallback
      final popupHtml = File('chronos_extension/popup.html').readAsStringSync();
      expect(popupHtml, contains('id="tab-btn-filters"'));
      expect(popupHtml, contains('id="tab-btn-sites"'));
      expect(popupHtml, contains('id="page-filters"'));
      expect(popupHtml, contains('id="page-sites"'));
      expect(popupHtml, contains('site-dropdown'));

      // 3. Verify Chrome & Firefox background.js both implement SSE /api/events + autocomplete + language handlers
      for (final extDir in ['chronos_extension', 'chronos_extension_firefox']) {
        final bgJs = File('$extDir/background.js').readAsStringSync();
        expect(bgJs, contains('/api/events'));
        expect(bgJs, contains('CHRONOS_STATE_PUSH'));
        expect(bgJs, contains('SEARCH_STEAM_AUTOCOMPLETE'));
        expect(bgJs, contains('SET_PRIMARY_LANGUAGE'));
      }

      // 4. Execute popup.js in Node with mocked DOM/chrome to verify tabs, dropdowns, no raw JSON, and CHRONOS_STATE_PUSH
      const popupScript = r'''
const fs = require("fs");
const assert = require("assert");
const vm = require("vm");

function makeStubElement(id) {
  const listeners = {};
  const attrs = {};
  const el = {
    id,
    innerText: "",
    textContent: "",
    _innerHTML: "",
    style: {},
    className: "",
    value: "",
    checked: false,
    disabled: false,
    hidden: false,
    open: false,
    children: [],
    childElementCount: 0,
    dataset: {},
    classList: {
      _set: new Set(),
      add(c) { this._set.add(c); },
      remove(c) { this._set.delete(c); },
      toggle(c, force) {
        if (force === undefined) {
          if (this._set.has(c)) this._set.delete(c);
          else this._set.add(c);
        } else if (force) {
          this._set.add(c);
        } else {
          this._set.delete(c);
        }
      },
      contains(c) { return this._set.has(c); },
    },
    set innerHTML(val) {
      this._innerHTML = String(val || "");
      this.childElementCount = this.children.length;
    },
    get innerHTML() { return this._innerHTML; },
    addEventListener(evt, fn) {
      listeners[evt] = listeners[evt] || [];
      listeners[evt].push(fn);
    },
    dispatch(evt, evObj) {
      for (const fn of listeners[evt] || []) fn(evObj || {});
    },
    setAttribute(k, v) { attrs[k] = String(v); },
    getAttribute(k) { return attrs[k] ?? null; },
    removeAttribute(k) { delete attrs[k]; },
    appendChild(child) {
      this.children.push(child);
      this.childElementCount = this.children.length;
      return child;
    },
    querySelectorAll() { return []; },
    querySelector() { return null; },
    closest() { return null; },
  };
  return el;
}

const byId = new Map();
function getEl(id) {
  if (!byId.has(id)) byId.set(id, makeStubElement(id));
  return byId.get(id);
}

// Seed initial tab classes matching popup.html
getEl("tab-btn-filters").classList.add("is-active");
getEl("page-sites").classList.add("is-hidden");

const sentMessages = [];
const runtimeListeners = [];

const statusPayload = {
  isConnected: true,
  primaryLanguage: "pt-BR",
  tagDisplayMap: { NSFW: "Conteúdo Adulto", "Souls-like": "Estilo Souls" },
  antiCheatActive: false,
  focusFilters: {
    launcherFilterEnabled: true,
    launcherBlockedTags: ["NSFW"],
    launcherBlockedNames: ["Game X"],
    hudAlpha: 0.9,
    hudScale: 1.0,
    hudHideToEye: true,
  },
  sites: [
    {
      entityId: "group_focus_1",
      displayName: "Entretenimento",
      targetType: "GROUP",
      pattern: JSON.stringify({
        apps: [{ name: "YouTube", exec: "youtube" }],
        sites: ["youtube.com", "reddit.com", "twitch.tv"],
      }),
      remainingSeconds: 1200,
      isBlocked: false,
    },
  ],
};

let domLoadedHandler = null;
const fakeDoc = {
  getElementById: (id) => getEl(id),
  querySelectorAll: () => [],
  createElement: (tag) => makeStubElement(tag),
  addEventListener: (evt, fn) => {
    if (evt === "DOMContentLoaded") domLoadedHandler = fn;
  },
};

const fakeChrome = {
  runtime: {
    lastError: null,
    onMessage: {
      addListener: (fn) => runtimeListeners.push(fn),
    },
    sendMessage: (msg, cb) => {
      sentMessages.push(msg);
      if (msg.type === "GET_STATUS") {
        if (cb) cb(statusPayload);
      } else if (msg.type === "GET_LAUNCHER_TAGS") {
        if (cb) cb({ tags: [{ canonicalEn: "NSFW", displayName: "Conteúdo Adulto" }] });
      } else if (msg.type === "SEARCH_STEAM_AUTOCOMPLETE") {
        if (cb) {
          cb({
            results: [
              { canonicalEn: "Souls-like", displayName: "Estilo Souls", name: "Souls-like" },
            ],
          });
        }
      } else if (cb) {
        cb({ success: true });
      }
    },
  },
  tabs: {
    query: (_q, cb) => cb([{ id: 7, url: "https://www.youtube.com/watch?v=123" }]),
    sendMessage: (_id, _msg, cb) => cb && cb({ available: false }),
  },
};

const sandbox = {
  document: fakeDoc,
  window: { addEventListener: () => {} },
  chrome: fakeChrome,
  setInterval: () => 1,
  clearInterval: () => {},
  setTimeout,
  clearTimeout,
  fetch: async () => ({ ok: false }),
  console,
  URL,
  Set,
  Map,
  Array,
  Object,
  JSON,
  String,
  Number,
  Boolean,
  Promise,
};

const code = fs.readFileSync("chronos_extension/popup.js", "utf8");
vm.runInNewContext(code, sandbox);
assert.ok(domLoadedHandler, "popup.js must register DOMContentLoaded handler");
domLoadedHandler();

// Assert Sites pane rendered interactive <details class="site-dropdown"> without leaking raw JSON
const sitesHtml = getEl("sites-container").innerHTML;
assert.ok(sitesHtml.includes('<details class="site-dropdown"'), "Group rules must render collapsible site-dropdown");
assert.ok(sitesHtml.includes("youtube.com"), "Dropdown must list group domain youtube.com");
assert.ok(sitesHtml.includes("reddit.com"), "Dropdown must list group domain reddit.com");
assert.ok(sitesHtml.includes("twitch.tv"), "Dropdown must list group domain twitch.tv");
assert.ok(!sitesHtml.includes('{"apps":'), "Raw JSON must never appear in rendered site list");
assert.strictEqual(getEl("tab-status-pill").innerText, "Tempo restante: 20m 00s");

// Assert top tab separation switches visibility cleanly
getEl("tab-btn-sites").dispatch("click");
assert.strictEqual(getEl("page-filters").classList.contains("is-hidden"), true);
assert.strictEqual(getEl("page-sites").classList.contains("is-hidden"), false);

// Assert CHRONOS_STATE_PUSH updates live DOM immediately
assert.ok(runtimeListeners.length >= 1, "popup.js must listen for CHRONOS_STATE_PUSH");
runtimeListeners[0]({
  type: "CHRONOS_STATE_PUSH",
  isConnected: true,
  primaryLanguage: "en-US",
  tagDisplayMap: { NSFW: "NSFW" },
  sites: [
    {
      entityId: "group_focus_1",
      displayName: "Entretenimento",
      targetType: "GROUP",
      pattern: JSON.stringify({ apps: [], sites: ["vimeo.com", "dailymotion.com"] }),
      remainingSeconds: 0,
      isBlocked: true,
    },
  ],
});
assert.ok(getEl("sites-container").innerHTML.includes("vimeo.com"));
assert.ok(getEl("sites-container").innerHTML.includes("BLOQUEADO"));

// Assert localized autocomplete message dispatch works
const tagInput = getEl("f-launcher-tag-in");
tagInput.value = "souls";
tagInput.dispatch("input");
setTimeout(() => {
  const acCalls = sentMessages.filter((m) => m.type === "SEARCH_STEAM_AUTOCOMPLETE");
  assert.ok(acCalls.length >= 1, "Typing in tag input must trigger SEARCH_STEAM_AUTOCOMPLETE");
  console.log("POPUP_REFORM_OK");
}, 320);
''';

      final popupNodeRes = await Process.run('node', ['-e', popupScript]);
      expect(popupNodeRes.exitCode, equals(0), reason: 'stderr: ${popupNodeRes.stderr}');
      expect(popupNodeRes.stdout.toString(), contains('POPUP_REFORM_OK'));
    });

    test('Deactivating Anti-Burla clears antiCheatActive across SSE background & HUD', () async {
      final nodeScript = r'''
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

function extractBetween(src, startMarker, endMarker) {
  const s = src.indexOf(startMarker);
  const e = src.indexOf(endMarker, s);
  if (s === -1 || e === -1) throw new Error("Marker not found: " + startMarker);
  return src.slice(s, e);
}

const bgSrc = fs.readFileSync("chronos_extension/background.js", "utf8");
const handleSseBody = extractBetween(
  bgSrc,
  "function handleSseEventBlock(",
  "async function startSseStream("
);

const storageSetCalls = [];
const pushedMessages = [];
const tabMessages = [];
const bgSandbox = {
  isConnected: false,
  antiCheatActive: true,
  antiCheatMode: "CHALLENGE",
  cachedFocusFilters: { launcherFilterEnabled: true, launcherBlockedTags: ["NSFW"], launcherBlockedNames: [] },
  cachedTagDisplayMap: { NSFW: "NSFW" },
  cachedPrimaryLanguage: "pt-BR",
  lastServerRevision: "rev_1",
  filterRevision: 1,
  chrome: {
    storage: { local: { set: (obj) => storageSetCalls.push(obj) } },
  },
  broadcastFocusFilters: (f) => tabMessages.push({ filters: f, antiCheatActive: bgSandbox.antiCheatActive }),
  broadcastStatePush: () => pushedMessages.push({ antiCheatActive: bgSandbox.antiCheatActive, antiCheatMode: bgSandbox.antiCheatMode }),
  syncWithChronos: () => {},
  JSON,
  String,
  Object,
};
vm.runInNewContext(handleSseBody, bgSandbox);

bgSandbox.handleSseEventBlock(
  'event: chronos_update\ndata: ' + JSON.stringify({
    revision: "rev_2",
    antiCheatActive: false,
    antiCheatMode: "OFF",
    primaryLanguage: "pt-BR",
    tagDisplayMap: { NSFW: "NSFW" },
    focusFilters: { launcherFilterEnabled: true, launcherBlockedTags: ["NSFW"], launcherBlockedNames: [] },
  })
);

assert.strictEqual(bgSandbox.antiCheatActive, false, "SSE chronos_update must clear antiCheatActive");
assert.strictEqual(bgSandbox.antiCheatMode, "OFF", "SSE chronos_update must reset antiCheatMode");
assert.ok(storageSetCalls.some((o) => o.antiCheatActive === false && o.antiCheatMode === "OFF"));
assert.ok(pushedMessages.some((m) => m.antiCheatActive === false && m.antiCheatMode === "OFF"));
assert.ok(tabMessages.some((m) => m.antiCheatActive === false));

// Test focus_hud_panel updates remove buttons from 🔒 back to × when syncFilters receives antiCheatActive=false
const path = require("path");
const core = require(path.resolve("chronos_extension/focus_filters_core.js"));
const hudPanel = require(path.resolve("chronos_extension/focus_hud_panel.js"));

global.ChronosFocusCore = core;
const createdShadows = [];
function makeEl(tag) {
  let _text = "";
  const el = {
    tagName: String(tag || "div").toUpperCase(),
    id: "",
    type: "",
    value: "",
    checked: false,
    className: "",
    get textContent() { return _text; },
    set textContent(v) {
      _text = v === undefined || v === null ? "" : String(v);
      if (_text === "") el.children.length = 0;
    },
    title: "",
    children: [],
    parentNode: null,
    isConnected: false,
    style: { setProperty: () => {} },
    classList: {
      toggle: () => {},
      add: () => {},
      remove: () => {},
      contains: () => false,
    },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 120, height: 32, right: 120, bottom: 32 }),
    listeners: {},
    setAttribute: (k, v) => { el[k] = v; },
    getAttribute: (k) => el[k],
    addEventListener: (ev, fn) => {
      el.listeners[ev] = el.listeners[ev] || [];
      el.listeners[ev].push(fn);
    },
    dispatchEvent: (ev) => {
      const fns = el.listeners[ev.type] || [];
      fns.forEach((fn) => fn(ev));
    },
    appendChild: (c) => {
      c.parentNode = el;
      c.isConnected = true;
      el.children.push(c);
      return c;
    },
    attachShadow: () => {
      const sr = {
        children: [],
        appendChild: (c) => { sr.children.push(c); return c; },
        getElementById: () => null,
      };
      createdShadows.push(sr);
      return sr;
    },
  };
  return el;
}
function findAllByClass(root, cls, out = []) {
  if (!root) return out;
  if (typeof root.className === "string" && root.className.split(/\s+/).includes(cls)) {
    out.push(root);
  }
  if (Array.isArray(root.children)) {
    root.children.forEach((c) => findAllByClass(c, cls, out));
  }
  return out;
}
const body = makeEl("body");
global.window = {
  innerWidth: 1280,
  innerHeight: 800,
  location: { hostname: "store.steampowered.com" },
  addEventListener: () => {},
  removeEventListener: () => {},
  getComputedStyle: () => ({}),
};
global.window.top = global.window;
global.window.self = global.window;
global.document = {
  body,
  hidden: false,
  documentElement: makeEl("html"),
  createElement: (tag) => makeEl(tag),
  createElementNS: (_ns, tag) => makeEl(tag),
  querySelector: () => null,
  addEventListener: () => {},
  removeEventListener: () => {},
};
let currentAc = true;
const savedCalls = [];
const hud = hudPanel.create({
  source: "proxy",
  antiCheatActive: true,
  getAntiCheatActive: () => currentAc,
  getInitialFilters: () => ({ launcherFilterEnabled: true, launcherBlockedTags: ["NSFW"], launcherBlockedNames: [] }),
  onSaveFilters: (nextF, done) => {
    savedCalls.push(nextF);
    done({ success: true, antiCheatActive: false, filters: nextF });
  },
});
hud.ensureMounted();
assert.ok(createdShadows.length >= 1, "HUD must attach shadow DOM");
const lockedButtons = findAllByClass({ children: createdShadows[0].children }, "c-chip-rm");
assert.strictEqual(lockedButtons.length, 1);
assert.strictEqual(lockedButtons[0].textContent, "\uD83D\uDD12", "Remove button must show lock when Anti-Burla active");
lockedButtons[0].dispatchEvent({ type: "click", stopPropagation: () => {} });
assert.strictEqual(savedCalls.length, 0, "Clicking locked chip must NOT save removal");

currentAc = false;
hud.syncFilters(null, null, "pt-BR", false);
const unlockedButtons = findAllByClass({ children: createdShadows[0].children }, "c-chip-rm");
assert.strictEqual(unlockedButtons.length, 1);
assert.strictEqual(unlockedButtons[0].textContent, "\u00D7", "Remove button must revert to × immediately when Anti-Burla turns OFF");
unlockedButtons[0].dispatchEvent({ type: "click", stopPropagation: () => {} });
assert.strictEqual(savedCalls.length, 1, "Clicking unlocked chip must save removal");
assert.deepStrictEqual(savedCalls[0].launcherBlockedTags, []);
console.log("ANTICHEAT_OFF_SYNC_OK");
''';
      final res = await Process.run('node', ['-e', nodeScript]);
      expect(res.exitCode, equals(0), reason: 'stderr: ${res.stderr}');
      expect(res.stdout.toString(), contains('ANTICHEAT_OFF_SYNC_OK'));
    });
  });
}
