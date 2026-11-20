import 'dart:convert';
import 'dart:io';

import 'package:chronos_app/services/chronos_guard_service.dart';
import 'app_profile.dart';
import 'package:chronos_app/services/extension_packager.dart';

class DetectedBrowser {
  final String id;
  final String name;
  final String family; // 'chromium' or 'firefox'
  final String executable;
  final String configDir;
  final bool isConfigured;
  final bool isFlatpak;
  final String? flatpakAppId;
  final String? policyPath;

  DetectedBrowser({
    required this.id,
    required this.name,
    required this.family,
    required this.executable,
    required this.configDir,
    this.isConfigured = true,
    this.isFlatpak = false,
    this.flatpakAppId,
    this.policyPath,
  });
}

class BrowserInstallResult {
  final bool success;
  final List<DetectedBrowser> browsers;
  final String extensionPath;
  final String extensionId;
  final String message;

  BrowserInstallResult({
    required this.success,
    required this.browsers,
    required this.extensionPath,
    required this.extensionId,
    required this.message,
  });
}

class BrowserInstallReport {
  final bool success;
  final String message;
  final List<String> configuredBrowsers;
  final String chromeExtensionPath;
  final String firefoxExtensionPath;

  BrowserInstallReport({
    required this.success,
    required this.message,
    required this.configuredBrowsers,
    required this.chromeExtensionPath,
    required this.firefoxExtensionPath,
  });
}

class _BrowserSpec {
  final String id;
  final String name;
  final String family;
  final List<String> binaries;
  final List<String> relConfigDirs;
  final String? policyPath;
  final String? flatpakAppId;
  final String? flatpakRelConfig;

  const _BrowserSpec({
    required this.id,
    required this.name,
    required this.family,
    required this.binaries,
    required this.relConfigDirs,
    this.policyPath,
    this.flatpakAppId,
    this.flatpakRelConfig,
  });
}

/// Manages browser detection, clean CRX3/XPI/PAC deployment, Flatpak overrides,
/// stale-artifact cleanup, and truthful verification of extension/proxy protection.
class BrowserExtensionInstaller {
  static String get extensionId => ExtensionPackager.defaultChromeExtensionId;
  static const String firefoxAddonId = ExtensionPackager.firefoxAddonId;

  static const List<String> _staleExternalIds = [
    'aegenccmklmkblcmnloicgidcmhmnjmf',
    'aninfjdhjaoefbcceehflebadbippdpj',
    'bgfmonmknfnphmfmfldlemjmpjkjaelo',
  ];

  static const List<_BrowserSpec> _browserSpecs = [
    _BrowserSpec(
      id: 'chrome',
      name: 'Google Chrome',
      family: 'chromium',
      binaries: ['google-chrome', 'google-chrome-stable', '/opt/google/chrome/google-chrome'],
      relConfigDirs: ['.config/google-chrome'],
      policyPath: '/etc/opt/chrome/policies/managed/chronos-focus.json',
      flatpakAppId: 'com.google.Chrome',
      flatpakRelConfig: 'config/google-chrome',
    ),
    _BrowserSpec(
      id: 'chrome-beta',
      name: 'Google Chrome Beta',
      family: 'chromium',
      binaries: ['google-chrome-beta', '/opt/google/chrome-beta/google-chrome'],
      relConfigDirs: ['.config/google-chrome-beta'],
      policyPath: '/etc/opt/chrome-beta/policies/managed/chronos-focus.json',
    ),
    _BrowserSpec(
      id: 'chrome-unstable',
      name: 'Google Chrome Unstable',
      family: 'chromium',
      binaries: ['google-chrome-unstable', '/opt/google/chrome-unstable/google-chrome'],
      relConfigDirs: ['.config/google-chrome-unstable'],
      policyPath: '/etc/opt/chrome-unstable/policies/managed/chronos-focus.json',
    ),
    _BrowserSpec(
      id: 'chromium',
      name: 'Chromium',
      family: 'chromium',
      binaries: ['chromium', 'chromium-browser', '/usr/bin/chromium', '/snap/bin/chromium'],
      relConfigDirs: ['.config/chromium'],
      policyPath: '/etc/chromium/policies/managed/chronos-focus.json',
      flatpakAppId: 'org.chromium.Chromium',
      flatpakRelConfig: 'config/chromium',
    ),
    _BrowserSpec(
      id: 'brave',
      name: 'Brave Browser',
      family: 'chromium',
      binaries: ['brave', 'brave-browser', 'brave-bin', '/opt/brave.com/brave/brave', '/snap/bin/brave'],
      relConfigDirs: ['.config/BraveSoftware/Brave-Browser'],
      policyPath: '/etc/brave/policies/managed/chronos-focus.json',
      flatpakAppId: 'com.brave.Browser',
      flatpakRelConfig: 'config/BraveSoftware/Brave-Browser',
    ),
    _BrowserSpec(
      id: 'edge',
      name: 'Microsoft Edge',
      family: 'chromium',
      binaries: ['microsoft-edge', 'microsoft-edge-stable', '/opt/microsoft/msedge/msedge'],
      relConfigDirs: ['.config/microsoft-edge'],
      policyPath: '/etc/opt/edge/policies/managed/chronos-focus.json',
      flatpakAppId: 'com.microsoft.Edge',
      flatpakRelConfig: 'config/microsoft-edge',
    ),
    _BrowserSpec(
      id: 'vivaldi',
      name: 'Vivaldi',
      family: 'chromium',
      binaries: ['vivaldi', 'vivaldi-stable', '/opt/vivaldi/vivaldi'],
      relConfigDirs: ['.config/vivaldi'],
      policyPath: '/etc/vivaldi/policies/managed/chronos-focus.json',
      flatpakAppId: 'com.vivaldi.Vivaldi',
      flatpakRelConfig: 'config/vivaldi',
    ),
    _BrowserSpec(
      id: 'opera',
      name: 'Opera',
      family: 'chromium',
      binaries: ['opera', '/usr/lib/opera/opera', '/snap/bin/opera'],
      relConfigDirs: ['.config/opera'],
      policyPath: '/etc/opera/policies/managed/chronos-focus.json',
      flatpakAppId: 'com.opera.Opera',
      flatpakRelConfig: 'config/opera',
    ),
    _BrowserSpec(
      id: 'thorium',
      name: 'Thorium',
      family: 'chromium',
      binaries: ['thorium-browser', '/opt/thorium/thorium-browser'],
      relConfigDirs: ['.config/thorium'],
      policyPath: '/etc/thorium/policies/managed/chronos-focus.json',
    ),
    _BrowserSpec(
      id: 'firefox',
      name: 'Firefox',
      family: 'firefox',
      binaries: ['firefox', '/opt/firefox-bin/firefox', '/usr/bin/firefox', '/snap/bin/firefox'],
      relConfigDirs: ['.config/mozilla/firefox', '.mozilla/firefox'],
      policyPath: '/etc/firefox/policies/policies.json',
      flatpakAppId: 'org.mozilla.firefox',
      flatpakRelConfig: '.mozilla/firefox',
    ),
    _BrowserSpec(
      id: 'firefox-esr',
      name: 'Firefox ESR',
      family: 'firefox',
      binaries: ['firefox-esr', '/usr/bin/firefox-esr'],
      relConfigDirs: ['.mozilla/firefox'],
      policyPath: '/etc/firefox-esr/policies/policies.json',
    ),
    _BrowserSpec(
      id: 'librewolf',
      name: 'LibreWolf',
      family: 'firefox',
      binaries: ['librewolf', '/usr/bin/librewolf'],
      relConfigDirs: ['.librewolf'],
      policyPath: '/etc/librewolf/policies/policies.json',
      flatpakAppId: 'io.gitlab.librewolf-community',
      flatpakRelConfig: '.librewolf',
    ),
    _BrowserSpec(
      id: 'zen',
      name: 'Zen Browser',
      family: 'firefox',
      binaries: ['zen-browser', '/opt/zen-browser-bin/zen-bin'],
      relConfigDirs: ['.zen'],
      policyPath: '/etc/zen-browser/policies/policies.json',
      flatpakAppId: 'app.zen_browser.zen',
      flatpakRelConfig: '.zen',
    ),
    _BrowserSpec(
      id: 'floorp',
      name: 'Floorp',
      family: 'firefox',
      binaries: ['floorp', '/usr/bin/floorp', '/opt/floorp/floorp'],
      relConfigDirs: ['.floorp'],
      policyPath: '/etc/floorp/policies/policies.json',
      flatpakAppId: 'one.ablaze.floorp',
      flatpakRelConfig: '.floorp',
    ),
    _BrowserSpec(
      id: 'waterfox',
      name: 'Waterfox',
      family: 'firefox',
      binaries: ['waterfox', '/usr/bin/waterfox', '/opt/waterfox/waterfox'],
      relConfigDirs: ['.waterfox'],
      policyPath: '/etc/waterfox/policies/policies.json',
      flatpakAppId: 'net.waterfox.waterfox',
      flatpakRelConfig: '.waterfox',
    ),
  ];

  static Future<BrowserInstallReport>? _inFlightInstall;

  static String getExtensionAbsolutePath() => getCanonicalExtensionDir();

  static String getChromeExtensionDir() {
    final root = ExtensionPackager.findProjectRoot();
    if (root != null) {
      final candidate = '$root/chronos_extension';
      if (File('$candidate/manifest.json').existsSync()) return candidate;
    }
    return getCanonicalExtensionDir();
  }

  static String getFirefoxExtensionDir() {
    final root = ExtensionPackager.findProjectRoot();
    if (root != null) {
      final candidate = '$root/chronos_extension_firefox';
      if (File('$candidate/manifest.json').existsSync()) return candidate;
    }
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/.local/share/chronos/firefox_extension_stage';
  }

  static String getCanonicalExtensionDir() {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final canonical = '$home/.local/share/chronos/extension';
    if (File('$canonical/manifest.json').existsSync()) return canonical;
    return getChromeExtensionDir();
  }

  /// Legacy unpacked SHA-256 -> Chrome a..p ID helper preserved for diagnostics.
  static String computeUnpackedExtensionId(String absolutePath) {
    return extensionId;
  }

  static Future<List<DetectedBrowser>> detectBrowsers({String? homeOverride}) =>
      detectInstalledBrowsers(homeOverride: homeOverride);

  static String? _findExecutableInPath(String name) {
    final pathEnv = Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
    for (final dir in pathEnv.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir/$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  /// Scans `.desktop` entries as a fallback for custom-installed browsers not on PATH.
  static String? _findDesktopExecutableForSpec(_BrowserSpec spec, String home) {
    final appDirs = [
      Directory('$home/.local/share/applications'),
      Directory('/usr/local/share/applications'),
      Directory('/usr/share/applications'),
    ];
    // Only command names (not the last segment of absolute paths: '/opt/google/chrome-beta/
    // google-chrome' would match the stable 'google-chrome.desktop' and invent Chrome Beta).
    final names = spec.binaries
        .where((b) => !b.startsWith('/'))
        .map((b) => b.toLowerCase())
        .where((b) => b.isNotEmpty)
        .toSet();
    for (final dir in appDirs) {
      if (!dir.existsSync()) continue;
      try {
        for (final entry in dir.listSync()) {
          if (entry is! File || !entry.path.endsWith('.desktop')) continue;
          final base = entry.uri.pathSegments.last.toLowerCase();
          final stem = base.endsWith('.desktop') ? base.substring(0, base.length - 8) : base;
          if (!names.contains(stem) && stem != spec.id) continue;
          final lines = entry.readAsLinesSync();
          for (final line in lines) {
            if (!line.startsWith('Exec=')) continue;
            final rawCmd = line.substring(5).trim().split(RegExp(r'\s+')).first.replaceAll('"', '');
            if (rawCmd.isNotEmpty && File(rawCmd).existsSync()) {
              return rawCmd;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Detects native and Flatpak browsers without clobbering Flatpak app IDs.
  static Future<List<DetectedBrowser>> detectInstalledBrowsers({
    String? homeOverride,
    String? flatpakListOutputOverride,
    bool skipBinaryCheckForTest = false,
  }) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final found = <DetectedBrowser>[];

    for (final spec in _browserSpecs) {
      String? resolvedExe;
      if (!skipBinaryCheckForTest) {
        for (final bin in spec.binaries) {
          if (bin.startsWith('/')) {
            if (File(bin).existsSync()) {
              resolvedExe = bin;
              break;
            }
          } else {
            resolvedExe = _findExecutableInPath(bin);
            if (resolvedExe != null) break;
          }
        }
        resolvedExe ??= _findDesktopExecutableForSpec(spec, home);
      }

      String? existingCfg;
      for (final rel in spec.relConfigDirs) {
        final d = Directory('$home/$rel');
        if (d.existsSync()) {
          existingCfg = d.path;
          break;
        }
      }

      // Never report two browsers for the same executable.
      if (resolvedExe != null && found.any((b) => b.executable == resolvedExe)) {
        resolvedExe = null;
      }
      if (resolvedExe != null || (skipBinaryCheckForTest && existingCfg != null)) {
        found.add(DetectedBrowser(
          id: spec.id,
          name: spec.name,
          family: spec.family,
          executable: resolvedExe ?? spec.binaries.first,
          configDir: existingCfg ?? '$home/${spec.relConfigDirs.first}',
          isConfigured: existingCfg != null,
          isFlatpak: false,
          policyPath: spec.policyPath,
        ));
      }
    }

    // Detect Flatpak installations cleanly preserving unique IDs & App IDs.
    String flatpakAppsRaw = flatpakListOutputOverride ?? '';
    if (flatpakListOutputOverride == null && !skipBinaryCheckForTest && _findExecutableInPath('flatpak') != null) {
      try {
        final fpRes = await Process.run('flatpak', ['list', '--app', '--columns=application']);
        if (fpRes.exitCode == 0) {
          flatpakAppsRaw = fpRes.stdout.toString();
        }
      } catch (_) {}
    }

    final installedFlatpaks = flatpakAppsRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    for (final spec in _browserSpecs) {
      final fpId = spec.flatpakAppId;
      if (fpId == null || !installedFlatpaks.contains(fpId)) continue;
      final relCfg = spec.flatpakRelConfig ?? spec.relConfigDirs.first;
      final fpConfigDir = '$home/.var/app/$fpId/$relCfg';
      found.add(DetectedBrowser(
        id: 'flatpak:${spec.id}',
        name: '${spec.name} (Flatpak)',
        family: spec.family,
        executable: 'flatpak run $fpId',
        configDir: fpConfigDir,
        isConfigured: Directory(fpConfigDir).existsSync(),
        isFlatpak: true,
        flatpakAppId: fpId,
        policyPath: spec.policyPath,
      ));
    }

    return found;
  }

  static File _userRemovedFlagFile(String home) =>
      File('$home/.local/share/chronos/.extension_removed_by_user');

  /// Returns true when the user explicitly uninstalled extensions after passing Anti-Burla verification.
  static bool hasUserRemovedExtensionFlag({String? homeOverride}) {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    return _userRemovedFlagFile(home).existsSync();
  }

  static Future<void> clearUserRemovedExtensionFlag({String? homeOverride}) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final flag = _userRemovedFlagFile(home);
    if (flag.existsSync()) {
      try {
        await flag.delete();
      } catch (_) {}
    }
  }

  /// Chromium-based browsers poll extension updates only every few hours. On distros whose
  /// launchers read `~/.config/<browser>-flags.conf` (Arch and derivatives) we add
  /// `--extensions-update-frequency=30`, so new Chronos builds reach the browser within
  /// ~30 seconds without pressing "Update" (takes effect the next time the browser starts).
  static const String extensionUpdateFlag = '--extensions-update-frequency=30';

  static void ensureExtensionUpdateFrequencyFlags({String? homeOverride}) {
    final home = homeOverride ?? Platform.environment['HOME'];
    if (home == null) return;
    final configHome = homeOverride == null ? (Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config') : '$home/.config';
    const browsers = <String, List<String>>{
      'chrome-flags.conf': ['/usr/bin/google-chrome-stable', '/usr/bin/google-chrome'],
      'chromium-flags.conf': ['/usr/bin/chromium'],
      'brave-flags.conf': ['/usr/bin/brave', '/usr/bin/brave-browser'],
    };
    browsers.forEach((file, launchers) {
      if (!launchers.any((l) => File(l).existsSync())) return;
      try {
        final f = File('$configHome/$file');
        final current = f.existsSync() ? f.readAsStringSync() : '';
        final lines = current.split('\n').where((l) => !l.trim().startsWith('--extensions-update-frequency')).toList();
        while (lines.isNotEmpty && lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        lines.add(extensionUpdateFlag);
        final next = '${lines.join('\n')}\n';
        if (next.trimLeft() != current.trimLeft() || !current.contains(extensionUpdateFlag)) {
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(next.startsWith('\n') ? next.substring(1) : next);
        }
      } catch (_) {}
    });
  }

  /// Opens the Chronos extension page ("Allow in Incognito" toggle) in every installed
  /// Chromium-based browser. Firefox needs nothing: its policy already allows private windows.
  /// Returns the browsers that were opened.
  /// [skip]: browser ids (chrome, chromium, brave) whose extension already has access.
  static Future<List<String>> openIncognitoPermissionPages({Set<String> skip = const {}}) async {
    final opened = <String>[];
    const targets = <String, (List<String>, String, String)>{
      'Google Chrome': (['/usr/bin/google-chrome-stable', '/usr/bin/google-chrome'], 'chrome', 'chrome'),
      'Chromium': (['/usr/bin/chromium'], 'chrome', 'chromium'),
      'Brave': (['/usr/bin/brave', '/usr/bin/brave-browser'], 'brave', 'brave'),
    };
    for (final entry in targets.entries) {
      final (launchers, scheme, id) = entry.value;
      if (skip.contains(id)) continue;
      final exe = launchers.firstWhere((l) => File(l).existsSync(), orElse: () => '');
      if (exe.isEmpty) continue;
      try {
        await Process.start(exe, ['$scheme://extensions/?id=$extensionId'], mode: ProcessStartMode.detached);
        opened.add(entry.key);
      } catch (_) {}
    }
    return opened;
  }

  static Future<BrowserInstallResult> installAll({
    bool isAntiCheatActive = false,
    bool launchWithExtension = false,
    bool forceMandatory = false,
    String? homeOverride,
  }) async {
    if (ChronosProfile.isDev) {
      return BrowserInstallResult(success: false, browsers: const [], extensionPath: '', extensionId: extensionId, message: ChronosProfile.devUnavailableMessage);
    }
    if (forceMandatory || isAntiCheatActive) {
      await clearUserRemovedExtensionFlag(homeOverride: homeOverride);
    }
    ensureExtensionUpdateFrequencyFlags(homeOverride: homeOverride);
    final report = await installAllAutomatically(
      launchWithExtension: launchWithExtension,
      forceMandatory: forceMandatory || isAntiCheatActive,
      homeOverride: homeOverride,
    );
    final browsers = await detectInstalledBrowsers(
      homeOverride: homeOverride,
      skipBinaryCheckForTest: homeOverride != null,
    );
    return BrowserInstallResult(
      success: report.success,
      browsers: browsers,
      extensionPath: report.chromeExtensionPath,
      extensionId: extensionId,
      message: report.message,
    );
  }

  /// Cleans up legacy broken flags/JSONs, packages CRX3/XPI/CA/PAC, configures
  /// valid external_crx descriptors, Flatpak overrides, and silent Guard CRX updates.
  static Future<BrowserInstallReport> installAllAutomatically({
    bool launchWithExtension = false,
    bool forceMandatory = false,
    String? homeOverride,
  }) async {
    if (ChronosProfile.isDev) {
      return BrowserInstallReport(success: false, message: ChronosProfile.devUnavailableMessage, configuredBrowsers: const [], chromeExtensionPath: '', firefoxExtensionPath: '');
    }
    if (forceMandatory) {
      await clearUserRemovedExtensionFlag(homeOverride: homeOverride);
    }
    // Only coalesce concurrent default-home calls; isolated homeOverride calls run independently.
    if (homeOverride == null) {
      final inFlight = _inFlightInstall;
      if (inFlight != null) return inFlight;
    }

    final future = _installAllAutomaticallyImpl(
      launchWithExtension: launchWithExtension,
      homeOverride: homeOverride,
    );
    if (homeOverride == null) {
      _inFlightInstall = future;
    }
    try {
      return await future;
    } finally {
      if (homeOverride == null && identical(_inFlightInstall, future)) {
        _inFlightInstall = null;
      }
    }
  }

  static Future<BrowserInstallReport> _installAllAutomaticallyImpl({
    bool launchWithExtension = false,
    String? homeOverride,
  }) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final pkg = await ExtensionPackager.packageAll(homeDirOverride: homeOverride);
    if (!pkg.success) {
      return BrowserInstallReport(
        success: false,
        message: pkg.message,
        configuredBrowsers: const [],
        chromeExtensionPath: getCanonicalExtensionDir(),
        firefoxExtensionPath: getFirefoxExtensionDir(),
      );
    }

    // Skip privileged pkexec side-effects during sandboxed/homeOverride tests.
    final silentUpdateFuture = homeOverride == null
        ? ChronosGuardService.trySilentCrxUpdate()
        : Future.value(false);

    final browsers = await detectInstalledBrowsers(
      homeOverride: homeOverride,
      skipBinaryCheckForTest: homeOverride != null,
    );
    final configured = <String>[];

    // Remove duplicate `--load-extension` lines from Chrome/Chromium flag files
    // so only the policy-enforced / CRX3 copy runs cleanly.
    await _cleanupDuplicateChromiumFlags(home);

    final extCrxPath = pkg.crxPath ?? '$home/.local/share/chronos/chronos_extension.crx';

    for (final browser in browsers) {
      if (homeOverride == null && browser.isFlatpak && browser.flatpakAppId != null) {
        try {
          await Process.run('flatpak', [
            'override',
            '--user',
            '--filesystem=xdg-data/chronos:ro',
            '--filesystem=/usr/local/share/chronos:ro',
            browser.flatpakAppId!,
          ]);
        } catch (_) {}
      }

      if (browser.family == 'chromium') {
        await _configureChromiumBrowser(
          browser,
          extCrxPath,
          pkg.version,
          homeOverride: homeOverride,
        );
        configured.add(browser.name);
      } else if (browser.family == 'firefox') {
        await _cleanupOldFirefoxProfileXpis(browser.configDir, pkg.xpiPath);
        configured.add(browser.name);
      }
    }

    await silentUpdateFuture;

    // Clean any legacy Firefox XPIs and stale user-level Firefox policies.json across
    // secondary Mozilla profile roots so no unsigned addon errors linger in about:policies.
    await cleanupLegacyUserFirefoxPolicies(homeOverride: homeOverride);
    for (final spec in _browserSpecs.where((s) => s.family == 'firefox')) {
      for (final rel in spec.relConfigDirs) {
        await _cleanupOldFirefoxProfileXpis('$home/$rel', pkg.xpiPath);
      }
    }

    final pendingRestart = <String>[];
    for (final browser in browsers) {
      if (browser.family == 'chromium') {
        final diag = inspectChromiumProfiles(
          browser.configDir,
          expectedVersionOverride: pkg.version,
        );
        if (diag.hasOutdatedOrDisabled && isBrowserProcessRunning(browser)) {
          pendingRestart.add(browser.name);
        }
      }
    }

    final baseMsg = configured.isEmpty
        ? 'Pacotes v${pkg.version} atualizados.'
        : 'Configurado (CRX3 v${pkg.version} / Proxy): ${configured.join(', ')}';
    final fullMsg = pendingRestart.isEmpty
        ? baseMsg
        : '$baseMsg. Reinicie ${pendingRestart.join(', ')} para aplicar a versão v${pkg.version}.';

    return BrowserInstallReport(
      success: configured.isNotEmpty || pkg.success,
      message: fullMsg,
      configuredBrowsers: configured,
      chromeExtensionPath: '$home/.local/share/chronos/extension',
      firefoxExtensionPath: pkg.xpiPath ?? getFirefoxExtensionDir(),
    );
  }

  static Future<void> _cleanupDuplicateChromiumFlags(String home) async {
    for (final fname in [
      'chromium-flags.conf',
      'chrome-flags.conf',
      'brave-flags.conf',
      'edge-flags.conf',
    ]) {
      final f = File('$home/.config/$fname');
      if (!f.existsSync()) continue;
      try {
        final lines = await f.readAsLines();
        final filtered = lines.where((l) {
          final t = l.trim();
          if (t.startsWith('--load-extension=') && t.contains('chronos')) {
            return false;
          }
          return true;
        }).toList();
        if (filtered.length != lines.length) {
          final joined = filtered.join('\n').trimRight();
          await f.writeAsString(joined.isEmpty ? '' : '$joined\n', flush: true);
        }
      } catch (_) {}
    }
  }

  static Future<void> _configureChromiumBrowser(
    DetectedBrowser browser,
    String crxPath,
    String version, {
    String? homeOverride,
  }) async {
    final extDir = Directory('${browser.configDir}/External Extensions');
    final cfgExists = Directory(browser.configDir).existsSync();
    if (!cfgExists && !browser.isConfigured && homeOverride != null) {
      return;
    }
    try {
      await extDir.create(recursive: true);
      for (final staleId in _staleExternalIds) {
        final staleFile = File('${extDir.path}/$staleId.json');
        if (staleFile.existsSync()) await staleFile.delete();
      }
      final validDescriptor = File('${extDir.path}/$extensionId.json');
      await validDescriptor.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'external_crx': crxPath,
          'external_version': version,
        }),
        flush: true,
      );

      // Never delete extension folders or edit `Preferences` here: Chrome MAC-protects
      // its preferences, so such edits get reverted while the deleted folder stays gone,
      // leaving the extension "corrupted" (disable reason 1024). Updates now flow through
      // the policy update URL served by chronos_proxy (`/extension/update.xml`).
    } catch (_) {}
  }

  /// Removes legacy user-level Firefox `policies/policies.json` files left behind
  /// by older versions that pointed to `~/Downloads/chronos-focus@chronos.local.xpi`.
  static Future<void> cleanupLegacyUserFirefoxPolicies({String? homeOverride}) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    for (final rel in [
      '.mozilla/firefox/policies/policies.json',
      '.config/mozilla/firefox/policies/policies.json',
    ]) {
      final f = File('$home/$rel');
      if (!f.existsSync()) continue;
      try {
        final content = await f.readAsString();
        if (content.contains(firefoxAddonId) ||
            content.contains('chronos_blocker@chronos.local')) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> _cleanupOldFirefoxProfileXpis(
    String configDir,
    String? freshXpiPath,
  ) async {
    final root = Directory(configDir);
    if (!root.existsSync()) return;
    try {
      for (final entity in root.listSync()) {
        if (entity is! Directory) continue;
        final extDir = Directory('${entity.path}/extensions');
        if (!extDir.existsSync()) continue;
        final legacyXpi = File('${extDir.path}/chronos_blocker@chronos.local.xpi');
        if (legacyXpi.existsSync()) {
          await legacyXpi.delete();
        }
        // Keep fresh correctly-named XPI staged for permissive forks (LibreWolf/Zen/ESR).
        if (freshXpiPath != null && File(freshXpiPath).existsSync()) {
          await File(freshXpiPath).copy('${extDir.path}/$firefoxAddonId.xpi');
        }
      }
    } catch (_) {}
  }

  static String? _resolvePolicyPath(DetectedBrowser browser) {
    if (browser.policyPath != null) return browser.policyPath;
    for (final spec in _browserSpecs) {
      if (browser.id == spec.id ||
          browser.id == 'flatpak:${spec.id}' ||
          (browser.id == 'google-chrome' && spec.id == 'chrome')) {
        return spec.policyPath;
      }
    }
    return null;
  }

  /// Resolves the highest expected Chronos extension version from local packaging metadata or source manifest.
  static String getExpectedExtensionVersion({String? homeOverride}) {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    String best = '1.1.0';

    void consider(String? candidate) {
      if (candidate == null) return;
      final clean = candidate.trim();
      if (!RegExp(r'^[0-9]+(\.[0-9]+){1,3}$').hasMatch(clean)) return;
      if (ExtensionPackager.compareVersions(clean, best) > 0) {
        best = clean;
      }
    }

    final metaFile = File('$home/.local/share/chronos/.ext_build_meta.json');
    if (metaFile.existsSync()) {
      try {
        final decoded = jsonDecode(metaFile.readAsStringSync());
        if (decoded is Map) consider(decoded['version']?.toString());
      } catch (_) {}
    }

    final root = ExtensionPackager.findProjectRoot();
    if (root != null) {
      final srcMan = File('$root/chronos_extension/manifest.json');
      if (srcMan.existsSync()) {
        try {
          final decoded = jsonDecode(srcMan.readAsStringSync());
          if (decoded is Map) consider(decoded['version']?.toString());
        } catch (_) {}
      }
    }

    final guardConf = File('/usr/local/share/chronos/guard.conf');
    if (guardConf.existsSync()) {
      try {
        final content = guardConf.readAsStringSync();
        final m = RegExp(r'^VERSION="?([^"\n]+)"?', multiLine: true).firstMatch(content);
        consider(m?.group(1));
      } catch (_) {}
    }

    return best;
  }

  static Set<String> _executableNamesForBrowser(DetectedBrowser browser) {
    return <String>{
      browser.executable.split('/').last.split(' ').first,
      if (browser.id.contains('chrome')) 'chrome',
      if (browser.id.contains('chromium')) 'chromium',
      if (browser.id.contains('brave')) 'brave',
      if (browser.id.contains('edge')) 'msedge',
      if (browser.id.contains('vivaldi')) 'vivaldi-bin',
      if (browser.id.contains('opera')) 'opera',
      if (browser.family == 'firefox') 'firefox',
    }..removeWhere((e) => e.isEmpty || e == 'flatpak');
  }

  static List<int> _findRunningPidsForBrowser(DetectedBrowser browser) {
    final pids = <int>[];
    if (browser.configDir.isNotEmpty) {
      final lockFile = File('${browser.configDir}/SingletonLock');
      try {
        final target = lockFile.resolveSymbolicLinksSync();
        final pidStr = target.split('-').last;
        final parsedPid = int.tryParse(pidStr);
        if (parsedPid != null && parsedPid > 0 && Directory('/proc/$parsedPid').existsSync()) {
          pids.add(parsedPid);
        }
      } catch (_) {}
    }

    if (Platform.environment.containsKey('FLUTTER_TEST') ||
        browser.configDir.startsWith('/tmp/')) {
      return pids;
    }

    final targetBins = _executableNamesForBrowser(browser);
    try {
      for (final entry in Directory('/proc').listSync()) {
        final name = entry.path.split('/').last;
        final pidNum = int.tryParse(name);
        if (pidNum == null || pids.contains(pidNum)) continue;
        final cmdFile = File('${entry.path}/cmdline');
        if (!cmdFile.existsSync()) continue;
        final raw = cmdFile.readAsBytesSync();
        if (raw.isEmpty) continue;
        final args = utf8.decode(raw, allowMalformed: true).split('\x00');
        final exeName = args.isNotEmpty ? args.first.split('/').last : '';
        if (targetBins.contains(exeName)) {
          pids.add(pidNum);
        }
      }
    } catch (_) {}
    return pids;
  }

  /// Returns true if [browser] currently has an active running OS process.
  static bool isBrowserProcessRunning(DetectedBrowser browser) {
    return _findRunningPidsForBrowser(browser).isNotEmpty;
  }

  /// Returns Chromium-family browsers currently open in memory that still need a
  /// restart to load or update the Chronos CRX3 extension.
  static Future<List<DetectedBrowser>> findOpenPendingChromiumBrowsers({
    String? homeOverride,
    String? sysCrxPathOverride,
  }) async {
    final expected = getExpectedExtensionVersion(homeOverride: homeOverride);
    final browsers = await detectInstalledBrowsers(
      homeOverride: homeOverride,
      skipBinaryCheckForTest: homeOverride != null,
    );
    final openPending = <DetectedBrowser>[];
    for (final browser in browsers) {
      if (browser.family != 'chromium' || browser.configDir.isEmpty) continue;
      final diag = inspectChromiumProfiles(
        browser.configDir,
        expectedVersionOverride: expected,
      );
      final needsRestart = diag.hasOutdatedOrDisabled ||
          (!diag.hasActiveValid &&
              isChromiumPolicyReady(
                browser,
                homeOverride: homeOverride,
                sysCrxPathOverride: sysCrxPathOverride,
              ));
      if (needsRestart && isBrowserProcessRunning(browser)) {
        openPending.add(browser);
      }
    }
    return openPending;
  }

  /// Gracefully closes and relaunches a single confirmed [browser].
  static Future<bool> relaunchBrowser(DetectedBrowser browser) async {
    try {
      if (browser.isFlatpak && browser.flatpakAppId != null) {
        await Process.run('flatpak', ['kill', browser.flatpakAppId!]);
      } else {
        final pids = _findRunningPidsForBrowser(browser);
        for (final pidNum in pids) {
          Process.killPid(pidNum, ProcessSignal.sigterm);
        }
      }

      // Wait briefly for process teardown so SingletonLock clears before relaunching.
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (!isBrowserProcessRunning(browser)) break;
      }

      final parts = browser.executable.split(' ').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) return false;
      await Process.start(
        parts.first,
        parts.skip(1).toList(),
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inspects all profiles (`Default`, `Profile *`, etc.) inside [configDir] for outdated,
  /// disabled, or active valid Chronos extension installs.
  static ({
    bool hasAnyEntry,
    bool hasOutdatedOrDisabled,
    bool hasActiveValid,
    String? outdatedVersion,
  }) inspectChromiumProfiles(
    String configDir, {
    String? expectedVersionOverride,
  }) {
    final expected = expectedVersionOverride ?? getExpectedExtensionVersion();
    bool hasAnyEntry = false;
    bool hasOutdatedOrDisabled = false;
    bool hasActiveValid = false;
    String? outdatedVersion;

    final dir = Directory(configDir);
    if (!dir.existsSync()) {
      return (
        hasAnyEntry: false,
        hasOutdatedOrDisabled: false,
        hasActiveValid: false,
        outdatedVersion: null,
      );
    }

    final profiles = <Directory>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final base = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (base == 'Default' || base.startsWith('Profile ')) {
        profiles.add(entry);
      }
    }

    for (final prof in profiles) {
      // Chrome keeps old version folders (1.1.64_0, 1.1.67_0, ...) until it cleans up:
      // the installed version is the newest folder, not any of them.
      String? dirVersion;
      final extIdDir = Directory('${prof.path}/Extensions/$extensionId');
      if (extIdDir.existsSync()) {
        try {
          for (final sub in extIdDir.listSync()) {
            if (sub is! Directory) continue;
            final rawVer = sub.uri.pathSegments
                .lastWhere((s) => s.isNotEmpty, orElse: () => '')
                .split('_')
                .first;
            if (rawVer.isNotEmpty &&
                (dirVersion == null || ExtensionPackager.compareVersions(rawVer, dirVersion) > 0)) {
              dirVersion = rawVer;
            }
          }
        } catch (_) {}
      }
      if (dirVersion != null) {
        hasAnyEntry = true;
        if (ExtensionPackager.compareVersions(dirVersion, expected) < 0) {
          hasOutdatedOrDisabled = true;
          outdatedVersion ??= dirVersion;
        }
      }

      final prefFile = File('${prof.path}/Preferences');
      if (!prefFile.existsSync()) continue;
      try {
        final decoded = jsonDecode(prefFile.readAsStringSync());
        if (decoded is! Map) continue;
        final settings = decoded['extensions']?['settings'];
        if (settings is! Map) continue;
        final item = settings[extensionId];
        if (item is! Map) continue;

        hasAnyEntry = true;
        final state = item['state'];
        final disableReasons = item['disable_reasons'];
        final disabled = disableReasons is List && disableReasons.isNotEmpty;
        // Preferences is only rewritten from time to time: the folder version wins.
        final prefVer = (item['manifest'] is Map) ? item['manifest']['version']?.toString() : null;
        final effVer = dirVersion ?? ((prefVer != null && prefVer.isNotEmpty) ? prefVer : null);

        if (disabled || state == 0) {
          hasOutdatedOrDisabled = true;
          outdatedVersion ??= effVer;
        } else if (effVer != null && ExtensionPackager.compareVersions(effVer, expected) < 0) {
          hasOutdatedOrDisabled = true;
          outdatedVersion ??= effVer;
        } else {
          hasActiveValid = true;
        }
      } catch (_) {}
    }

    return (
      hasAnyEntry: hasAnyEntry,
      hasOutdatedOrDisabled: hasOutdatedOrDisabled,
      hasActiveValid: hasActiveValid,
      outdatedVersion: outdatedVersion,
    );
  }

  static bool _hasValidCr24Binary(String path) {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 512) return false;
    try {
      final raf = f.openSync()..setPositionSync(0);
      final header = raf.readSync(4);
      raf.closeSync();
      return header.length == 4 && ascii.decode(header, allowInvalid: true) == 'Cr24';
    } catch (_) {
      return false;
    }
  }

  /// Returns true when either the Guard enterprise policy or the user External Extensions
  /// descriptor points to an existing valid CRX3 package on disk.
  static bool isChromiumPolicyReady(
    DetectedBrowser browser, {
    String? homeOverride,
    String? sysCrxPathOverride,
  }) {
    final polPath = _resolvePolicyPath(browser);
    final sysCrxPath = sysCrxPathOverride ?? '/usr/local/share/chronos/chronos.crx';
    if (polPath != null && File(polPath).existsSync()) {
      try {
        final content = File(polPath).readAsStringSync();
        if (content.contains('ExtensionInstallForcelist') &&
            content.contains(extensionId) &&
            _hasValidCr24Binary(sysCrxPath)) {
          return true;
        }
      } catch (_) {}
    }

    if (browser.configDir.isNotEmpty) {
      final extDesc = File('${browser.configDir}/External Extensions/$extensionId.json');
      if (extDesc.existsSync()) {
        try {
          final parsed = jsonDecode(extDesc.readAsStringSync());
          if (parsed is Map && parsed['external_crx'] is String) {
            return _hasValidCr24Binary(parsed['external_crx'] as String);
          }
        } catch (_) {}
      }
    }
    return false;
  }

  /// Returns an actionable user message when [browser] has an outdated or pending extension state.
  static String? getBrowserPendingMessage(
    DetectedBrowser browser, {
    String? homeOverride,
    String? expectedVersionOverride,
    String? sysCrxPathOverride,
  }) {
    if (browser.family != 'chromium' || browser.configDir.isEmpty) return null;
    final expected = expectedVersionOverride ??
        getExpectedExtensionVersion(homeOverride: homeOverride);
    final diag = inspectChromiumProfiles(browser.configDir, expectedVersionOverride: expected);
    if (diag.hasOutdatedOrDisabled) {
      final fromVer = diag.outdatedVersion ?? 'desatualizada';
      if (isBrowserProcessRunning(browser)) {
        return 'Extensão $fromVer -> v$expected pendente: feche e reabra o ${browser.name}.';
      }
      return 'Extensão $fromVer -> v$expected pendente: abra o ${browser.name} ou clique em "Instalar / Atualizar em Todos os Navegadores".';
    }
    if (!diag.hasActiveValid &&
        isChromiumPolicyReady(
          browser,
          homeOverride: homeOverride,
          sysCrxPathOverride: sysCrxPathOverride,
        )) {
      if (isBrowserProcessRunning(browser)) {
        return 'Política v$expected configurada: feche e reabra o ${browser.name} para baixar a extensão.';
      }
      return 'Política v$expected configurada: abra o ${browser.name} para baixar a extensão.';
    }
    return null;
  }

  /// Inspects Firefox/Gecko proxy policy health and profile add-on activation separately.
  static ({bool proxyHealthy, bool hasAddonLoaded}) inspectFirefoxStatus(
    DetectedBrowser browser, {
    String? homeOverride,
    String? policyPathOverride,
    String? sysCaPathOverride,
    String? sysPacPathOverride,
  }) {
    bool proxyHealthy = false;
    bool hasAddonLoaded = false;

    final polPath =
        policyPathOverride ?? _resolvePolicyPath(browser) ?? '/etc/firefox/policies/policies.json';
    final caPath = sysCaPathOverride ?? '/usr/local/share/chronos/chronos-proxy-ca.crt';
    final pacPath = sysPacPathOverride ?? '/usr/local/share/chronos/proxy.pac';

    if (File(polPath).existsSync()) {
      try {
        final content = File(polPath).readAsStringSync();
        proxyHealthy = content.contains('chronos-proxy-ca.crt') &&
            content.contains('proxy.pac') &&
            File(caPath).existsSync() &&
            File(pacPath).existsSync();
      } catch (_) {}
    }

    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final cfgDirs = <String>{
      if (browser.configDir.isNotEmpty) browser.configDir,
    };
    if (browser.id == 'firefox') {
      cfgDirs.add('$home/.config/mozilla/firefox');
      cfgDirs.add('$home/.mozilla/firefox');
    }
    for (final dirPath in cfgDirs) {
      final cfgRoot = Directory(dirPath);
      if (!cfgRoot.existsSync()) continue;
      try {
        for (final entry in cfgRoot.listSync()) {
          if (entry is! Directory) continue;
          final extJson = File('${entry.path}/extensions.json');
          if (!extJson.existsSync()) continue;
          final parsed = jsonDecode(extJson.readAsStringSync());
          if (parsed is! Map || parsed['addons'] is! List) continue;
          for (final addon in parsed['addons'] as List) {
            if (addon is Map &&
                addon['id'] == firefoxAddonId &&
                addon['active'] == true &&
                addon['userDisabled'] != true &&
                addon['appDisabled'] != true) {
              hasAddonLoaded = true;
              break;
            }
          }
          if (hasAddonLoaded) break;
        }
      } catch (_) {}
      if (hasAddonLoaded) break;
    }

    return (proxyHealthy: proxyHealthy, hasAddonLoaded: hasAddonLoaded);
  }

  /// Returns true when the given Firefox/Gecko browser is protected by Guard CA/PAC proxy policy.
  static bool isFirefoxProxyHealthy(
    DetectedBrowser browser, {
    String? homeOverride,
    String? policyPathOverride,
    String? sysCaPathOverride,
    String? sysPacPathOverride,
  }) =>
      inspectFirefoxStatus(
        browser,
        homeOverride: homeOverride,
        policyPathOverride: policyPathOverride,
        sysCaPathOverride: sysCaPathOverride,
        sysPacPathOverride: sysPacPathOverride,
      ).proxyHealthy;

  /// Summarizes truthful installation state, label, and optional pending hint for UI chips.
  static ({bool installed, String statusLabel, String? pendingMessage}) describeBrowserStatus(
    DetectedBrowser browser, {
    String? homeOverride,
    String? policyPathOverride,
    String? sysCaPathOverride,
    String? sysPacPathOverride,
  }) {
    final isChrome =
        browser.executable.contains('google-chrome') || browser.id.contains('google-chrome');
    final isFirefox = browser.family == 'firefox';

    if (isFirefox) {
      final ff = inspectFirefoxStatus(
        browser,
        homeOverride: homeOverride,
        policyPathOverride: policyPathOverride,
        sysCaPathOverride: sysCaPathOverride,
        sysPacPathOverride: sysPacPathOverride,
      );
      final installed = ff.proxyHealthy || ff.hasAddonLoaded;
      final String statusLabel;
      if (ff.proxyHealthy && ff.hasAddonLoaded) {
        statusLabel = 'Extensão + Proxy Ativos';
      } else if (ff.proxyHealthy) {
        statusLabel = 'Proxy Seletivo Ativo';
      } else if (ff.hasAddonLoaded) {
        statusLabel = 'Extensão Ativa';
      } else {
        statusLabel = 'Requer Guard/Proxy';
      }
      return (installed: installed, statusLabel: statusLabel, pendingMessage: null);
    }

    final installed = isExtensionInstalledInBrowser(browser, homeOverride: homeOverride);
    final pendingMessage = getBrowserPendingMessage(browser, homeOverride: homeOverride);

    final String statusLabel;
    if (installed) {
      statusLabel = 'Extensão Ativa';
    } else if (pendingMessage != null) {
      statusLabel = 'Aguardando Abrir/Reiniciar';
    } else if (isChrome) {
      statusLabel = 'Requer Guard / Ativação';
    } else {
      statusLabel = 'Pendente';
    }

    return (
      installed: installed,
      statusLabel: statusLabel,
      pendingMessage: pendingMessage,
    );
  }

  /// Checks Chrome/Chromium profile `Preferences` (`extensions.settings[extensionId]`).
  static bool isExtensionLoadedInChromeProfiles({
    String? configDirOverride,
    String? expectedVersionOverride,
  }) {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final dirs = (configDirOverride != null && configDirOverride.isNotEmpty)
        ? <String>[configDirOverride]
        : <String>['$home/.config/google-chrome', '$home/.config/chromium'];
    for (final dirPath in dirs) {
      final diag = inspectChromiumProfiles(
        dirPath,
        expectedVersionOverride: expectedVersionOverride,
      );
      if (diag.hasOutdatedOrDisabled) return false;
      if (diag.hasActiveValid) return true;
    }
    return false;
  }

  /// Honestly verifies whether [browser] actually has the extension active in a profile
  /// (never reporting "Configurado" solely from policy/External Extensions stubs before browser launch).
  static bool isExtensionInstalledInBrowser(
    DetectedBrowser browser, {
    String? expectedVersionOverride,
    String? homeOverride,
  }) {
    if (browser.family == 'chromium') {
      final expected = expectedVersionOverride ??
          getExpectedExtensionVersion(homeOverride: homeOverride);
      final diag = browser.configDir.isNotEmpty
          ? inspectChromiumProfiles(browser.configDir, expectedVersionOverride: expected)
          : (hasAnyEntry: false, hasOutdatedOrDisabled: false, hasActiveValid: false, outdatedVersion: null);

      if (diag.hasOutdatedOrDisabled) {
        return false;
      }
      return diag.hasActiveValid;
    }

    if (browser.family == 'firefox') {
      final ff = inspectFirefoxStatus(browser, homeOverride: homeOverride);
      return ff.proxyHealthy || ff.hasAddonLoaded;
    }

    return false;
  }

  /// Removes Chronos extension descriptors and unpacked copies across all user browser profiles
  /// after Anti-Burla verification has succeeded, and records `.extension_removed_by_user`.
  static Future<void> removeExtensionFromUserBrowsers({String? homeOverride}) async {
    if (ChronosProfile.isDev) return;
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final flagFile = _userRemovedFlagFile(home);
    await flagFile.parent.create(recursive: true);
    await flagFile.writeAsString(DateTime.now().toIso8601String(), flush: true);

    final browsers = await detectInstalledBrowsers(
      homeOverride: homeOverride,
      skipBinaryCheckForTest: homeOverride != null,
    );

    for (final browser in browsers) {
      if (browser.family == 'chromium' && browser.configDir.isNotEmpty) {
        final extDir = Directory('${browser.configDir}/External Extensions');
        for (final id in [extensionId, ..._staleExternalIds]) {
          final desc = File('${extDir.path}/$id.json');
          if (desc.existsSync()) {
            try {
              await desc.delete();
            } catch (_) {}
          }
        }
      } else if (browser.family == 'firefox' && browser.configDir.isNotEmpty) {
        await _removeFirefoxProfileXpis(browser.configDir);
      }
    }

    await cleanupLegacyUserFirefoxPolicies(homeOverride: homeOverride);
    for (final spec in _browserSpecs.where((s) => s.family == 'firefox')) {
      for (final rel in spec.relConfigDirs) {
        await _removeFirefoxProfileXpis('$home/$rel');
      }
    }
  }

  static Future<void> _removeFirefoxProfileXpis(String configDir) async {
    final root = Directory(configDir);
    if (!root.existsSync()) return;
    try {
      for (final entity in root.listSync()) {
        if (entity is! Directory) continue;
        final extDir = Directory('${entity.path}/extensions');
        if (!extDir.existsSync()) continue;
        for (final name in ['$firefoxAddonId.xpi', 'chronos_blocker@chronos.local.xpi']) {
          final f = File('${extDir.path}/$name');
          if (f.existsSync()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static bool _isDeploymentReadyOnDisk(
    DetectedBrowser browser, {
    String? homeOverride,
  }) {
    if (browser.family == 'chromium') {
      final diag = inspectChromiumProfiles(
        browser.configDir,
        expectedVersionOverride: getExpectedExtensionVersion(homeOverride: homeOverride),
      );
      if (diag.hasOutdatedOrDisabled) return false;
      final descFile = File('${browser.configDir}/External Extensions/$extensionId.json');
      return descFile.existsSync();
    }
    if (browser.family == 'firefox') {
      return isExtensionInstalledInBrowser(browser, homeOverride: homeOverride);
    }
    return false;
  }

  static Future<bool> verifyAndAutoRepairExtensions({
    required bool hasActiveSiteRules,
    bool isAntiCheatActive = false,
    String? homeOverride,
  }) async {
    if (ChronosProfile.isDev) return false;
    if (isAntiCheatActive) {
      await clearUserRemovedExtensionFlag(homeOverride: homeOverride);
    } else if (hasUserRemovedExtensionFlag(homeOverride: homeOverride)) {
      return true;
    }

    final browsers = await detectInstalledBrowsers(
      homeOverride: homeOverride,
      skipBinaryCheckForTest: homeOverride != null,
    );
    bool needsRepair = false;
    for (final b in browsers) {
      if (!_isDeploymentReadyOnDisk(b, homeOverride: homeOverride)) {
        needsRepair = true;
        break;
      }
    }
    if (needsRepair) {
      await installAllAutomatically(
        launchWithExtension: false,
        forceMandatory: true,
        homeOverride: homeOverride,
      );
    } else if (homeOverride == null) {
      await ChronosGuardService.trySilentCrxUpdate();
    }
    return true;
  }

  static Future<String?> exportExtensionZipToDownloads({String? homeOverride}) async {
    final pkg = await ExtensionPackager.packageAll(homeDirOverride: homeOverride);
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final downloads = Directory('$home/Downloads');
    await downloads.create(recursive: true);

    final outZip = File('${downloads.path}/chronos-extension-v${pkg.version}.zip');
    if (outZip.existsSync()) await outZip.delete();
    final srcDir = File('$home/.local/share/chronos/extension/manifest.json').existsSync()
        ? '$home/.local/share/chronos/extension'
        : getCanonicalExtensionDir();
    final res = await Process.run('zip', ['-rq', '-X', outZip.path, '.'], workingDirectory: srcDir);
    if (res.exitCode == 0 && outZip.existsSync()) {
      return outZip.path;
    }
    return null;
  }

  static Future<String?> exportFirefoxExtensionZipToDownloads({String? homeOverride}) async {
    final pkg = await ExtensionPackager.packageAll(homeDirOverride: homeOverride);
    if (pkg.xpiPath == null || !File(pkg.xpiPath!).existsSync()) return null;
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final downloads = Directory('$home/Downloads');
    await downloads.create(recursive: true);
    final dst = '$home/Downloads/chronos-focus-firefox-v${pkg.version}.xpi';
    await File(pkg.xpiPath!).copy(dst);
    // Keep legacy ZIP filename updated too (identical XPI/ZIP bundle for temporary/manual loading).
    await File(pkg.xpiPath!).copy('$home/Downloads/chronos_firefox_extension.zip');
    return dst;
  }

  static Future<String> launchGoogleChromeWithExtensionGuide() async {
    await installAllAutomatically();
    final browsers = await detectInstalledBrowsers();
    final chromium = browsers.firstWhere(
      (b) => b.family == 'chromium',
      orElse: () => DetectedBrowser(
        id: 'chromium',
        name: 'Chromium',
        family: 'chromium',
        executable: 'google-chrome',
        configDir: '',
      ),
    );
    try {
      final parts = chromium.executable.split(' ');
      await Process.start(
        parts.first,
        [...parts.skip(1), 'chrome://extensions'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
    return getCanonicalExtensionDir();
  }

  static Future<bool> launchFirefoxInstallPrompt() async {
    final pkg = await ExtensionPackager.packageAll();
    final xpiPath = pkg.xpiPath;
    if (xpiPath == null || !File(xpiPath).existsSync()) return false;
    try {
      await Process.start('firefox', ['file://$xpiPath'], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> launchFirefoxWithExtensionGuide() async {
    await ChronosGuardService.prepareStaging();
    try {
      await Process.start('firefox', ['about:policies'], mode: ProcessStartMode.detached);
    } catch (_) {}
    return ChronosGuardService.stagingDir;
  }
}
