import 'package:chronos_app/services/app_locale.dart';
import 'dart:io';

import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/extension_packager.dart';
import 'package:path_provider/path_provider.dart';

import 'app_profile.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/src/rust/api/adult.dart' show getPrivateBrowsingBlock;

class ChronosGuardStatus {
  final bool isInstalled;
  final bool isRunning;
  final bool isChromeProtected;
  final bool isChromiumProtected;
  final bool isFirefoxProtected;
  final bool isFirefoxProxyProtected;
  final bool isBraveProtected;
  final bool isEdgeProtected;
  final bool isVivaldiProtected;
  final bool isOperaProtected;
  final bool isGuardOutdated;
  final String installedVersion;

  const ChronosGuardStatus({
    required this.isInstalled,
    required this.isRunning,
    required this.isChromeProtected,
    required this.isChromiumProtected,
    required this.isFirefoxProtected,
    this.isFirefoxProxyProtected = false,
    this.isBraveProtected = false,
    this.isEdgeProtected = false,
    this.isVivaldiProtected = false,
    this.isOperaProtected = false,
    this.isGuardOutdated = false,
    this.installedVersion = '',
  });

  bool get isFullyActive =>
      isInstalled &&
      !isGuardOutdated &&
      (isChromeProtected ||
          isChromiumProtected ||
          isBraveProtected ||
          isEdgeProtected ||
          isVivaldiProtected ||
          isOperaProtected ||
          isFirefoxProtected ||
          isRunning);
}

class UnifiedBrowserSetupResult {
  final bool success;
  final String message;
  final BrowserInstallResult installReport;
  final ChronosGuardStatus guardStatus;
  final List<DetectedBrowser> openPendingChromiumBrowsers;
  final bool polkitUnavailableOrCancelled;

  const UnifiedBrowserSetupResult({
    required this.success,
    required this.message,
    required this.installReport,
    required this.guardStatus,
    this.openPendingChromiumBrowsers = const [],
    this.polkitUnavailableOrCancelled = false,
  });
}

class ChronosGuardService {
  static const String stagingDir = '/tmp/chronos_guard_staging';
  static const String guardBinary = '/usr/local/lib/chronos/chronos-guard';
  static const String extensionId = ExtensionPackager.defaultChromeExtensionId;
  static const String chromiumExtensionUpdateUrl = 'http://127.0.0.1:4545/extension/update.xml';

  static bool _hasChromiumPolicy(String path) {
    final file = File(path);
    if (!file.existsSync()) return false;
    try {
      final content = file.readAsStringSync();
      return content.contains('ExtensionInstallForcelist') && content.contains(extensionId);
    } catch (_) {
      return false;
    }
  }

  /// Checks system-level anti-tamper guard installation, browser policies, and Firefox Proxy/CA setup.
  static Future<ChronosGuardStatus> checkStatus() async {
    bool isInstalled = File(guardBinary).existsSync();
    bool isRunning = false;
    bool isChromeProtected = _hasChromiumPolicy('/etc/opt/chrome/policies/managed/chronos-focus.json');
    bool isChromiumProtected = _hasChromiumPolicy('/etc/chromium/policies/managed/chronos-focus.json');
    bool isBraveProtected = _hasChromiumPolicy('/etc/brave/policies/managed/chronos-focus.json');
    bool isEdgeProtected = _hasChromiumPolicy('/etc/opt/edge/policies/managed/chronos-focus.json');
    bool isVivaldiProtected = _hasChromiumPolicy('/etc/vivaldi/policies/managed/chronos-focus.json');
    bool isOperaProtected = _hasChromiumPolicy('/etc/opera/policies/managed/chronos-focus.json');
    bool isFirefoxProtected = false;
    bool isFirefoxProxyProtected = false;
    bool isGuardOutdated = false;
    String installedVersion = '';

    // Chromium cannot self-update from `file://` update URLs; policies written by older
    // guards must be reinstalled to point at the loopback HTTP update endpoint.
    final chromePolicy = File('/etc/opt/chrome/policies/managed/chronos-focus.json');
    if (chromePolicy.existsSync()) {
      try {
        if (!chromePolicy.readAsStringSync().contains(chromiumExtensionUpdateUrl)) {
          isGuardOutdated = true;
        }
      } catch (_) {}
    }

    final firefoxPolicy = File('/etc/firefox/policies/policies.json');
    if (firefoxPolicy.existsSync()) {
      try {
        final content = firefoxPolicy.readAsStringSync();
        final hasRightId = content.contains(ExtensionPackager.firefoxAddonId);
        final hasWrongId = content.contains('chronos_blocker@chronos.local');
        final hasProxy = content.contains('chronos-proxy-ca.crt') &&
            content.contains('proxy.pac') &&
            File('/usr/local/share/chronos/chronos-proxy-ca.crt').existsSync() &&
            File('/usr/local/share/chronos/proxy.pac').existsSync();
        isFirefoxProxyProtected = hasProxy;
        isFirefoxProtected = hasProxy || (hasRightId && !hasWrongId);
        if (hasWrongId || !hasProxy) {
          isGuardOutdated = true;
        }
      } catch (_) {}
    }

    if (isInstalled) {
      try {
        final binContent = File(guardBinary).readAsStringSync();
        if (!binContent.contains('chronos-focus@chronos.local') ||
            !binContent.contains('chronos-proxy-ca.crt') ||
            !binContent.contains('xpi_has_mozilla_signature') ||
            !binContent.contains('cmd_set_incognito') ||
            !binContent.contains('ProxyPacUrl') ||
            !binContent.contains('prepare_versioned_xpi') ||
            (!binContent.contains('vault_sync') && findVaultBinary() != null) ||
            _vaultBinaryOutdated()) {
          isGuardOutdated = true;
        }
      } catch (_) {}

      final confFile = File('/usr/local/share/chronos/guard.conf');
      if (confFile.existsSync()) {
        try {
          final conf = confFile.readAsStringSync();
          final m = RegExp(r'^VERSION="?([^"\n]+)"?', multiLine: true).firstMatch(conf);
          if (m != null) installedVersion = m.group(1)?.trim() ?? '';
        } catch (_) {}
      }

      try {
        final res = await Process.run(guardBinary, ['status']);
        if (res.exitCode == 0) {
          final out = res.stdout.toString();
          if (out.contains('running=1')) isRunning = true;
          if (out.contains('policy=/etc/opt/chrome/policies/managed:ok')) isChromeProtected = true;
          if (out.contains('policy=/etc/chromium/policies/managed:ok')) isChromiumProtected = true;
          if (out.contains('policy=/etc/firefox/policies:ok_proxy')) {
            isFirefoxProtected = true;
            isFirefoxProxyProtected = true;
          }
        }
      } catch (_) {}
    }

    if (isChromeProtected ||
        isChromiumProtected ||
        isBraveProtected ||
        isEdgeProtected ||
        isVivaldiProtected ||
        isOperaProtected ||
        isFirefoxProtected) {
      isRunning = true;
    }

    return ChronosGuardStatus(
      isInstalled: isInstalled,
      isRunning: isRunning,
      isChromeProtected: isChromeProtected,
      isChromiumProtected: isChromiumProtected,
      isFirefoxProtected: isFirefoxProtected,
      isFirefoxProxyProtected: isFirefoxProxyProtected,
      isBraveProtected: isBraveProtected,
      isEdgeProtected: isEdgeProtected,
      isVivaldiProtected: isVivaldiProtected,
      isOperaProtected: isOperaProtected,
      isGuardOutdated: isGuardOutdated,
      installedVersion: installedVersion,
    );
  }

  /// Packages fresh CRX3/XPI/CA/PAC artifacts and stages [stagingDir]
  /// (never copying private CA keys into staging).
  static const String vaultBinary = '/usr/local/lib/chronos/chronos_vault';

  /// `chronos_vault` shipped next to the app (release) or built in the checkout.
  static String? findVaultBinary({String? projectRootOverride}) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final root = projectRootOverride ?? ExtensionPackager.findProjectRoot();
    for (final path in [
      '$exeDir/chronos_vault',
      if (root != null) '$root/rust/target/release/chronos_vault',
    ]) {
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
    }
    return null;
  }

  /// Installed root vault missing or different from the one shipped with this app.
  static bool _vaultBinaryOutdated() {
    final shipped = findVaultBinary();
    if (shipped == null) return false;
    final installed = File(vaultBinary);
    if (!installed.existsSync()) return true;
    try {
      return installed.lengthSync() != File(shipped).lengthSync();
    } catch (_) {
      return false;
    }
  }

  static Future<String> prepareStaging({
    String? stagingDirOverride,
    String? homeOverride,
    String? projectRootOverride,
  }) async {
    final targetStaging = stagingDirOverride ?? stagingDir;
    final pkg = await ExtensionPackager.packageAll(
      homeDirOverride: homeOverride,
      projectRootOverride: projectRootOverride,
    );
    final stage = Directory(targetStaging);
    if (!stage.existsSync()) {
      await stage.create(recursive: true);
    }

    final root = projectRootOverride ?? ExtensionPackager.findProjectRoot();
    final guardDir =
        root != null ? '$root/system/guard' : '${Directory.current.path}/system/guard';
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';

    final scriptSrc = File('$guardDir/chronos-guard');
    final installSrc = File('$guardDir/install-guard.sh');
    if (scriptSrc.existsSync()) {
      await scriptSrc.copy('$targetStaging/chronos-guard');
      await Process.run('chmod', ['0755', '$targetStaging/chronos-guard']);
    }
    if (installSrc.existsSync()) {
      await installSrc.copy('$targetStaging/install-guard.sh');
      await Process.run('chmod', ['0755', '$targetStaging/install-guard.sh']);
    }

    var blockPrivate = true;
    try {
      blockPrivate = getPrivateBrowsingBlock();
    } catch (_) {}
    final privateFlag = blockPrivate ? 1 : 0;
    // Layered anti-cheat: the root vault watches this user's database.
    final vaultSrc = findVaultBinary(projectRootOverride: root);
    if (vaultSrc != null) {
      await File(vaultSrc).copy('$targetStaging/chronos_vault');
      await Process.run('chmod', ['0755', '$targetStaging/chronos_vault']);
    }
    var dbPath = '$home/Documents/${ChronosProfile.dbFileName}';
    if (homeOverride == null) {
      try {
        dbPath = '${(await getApplicationDocumentsDirectory()).path}/${ChronosProfile.dbFileName}';
      } catch (_) {}
    }
    final targetUser = Platform.environment['USER'] ?? home.split('/').last;
    final confContent = '''# Configuração do Chronos Guard
EXTENSION_ID="${pkg.extensionId}"
FIREFOX_ADDON_ID="${ExtensionPackager.firefoxAddonId}"
VERSION="${pkg.version}"
BLOCK_INCOGNITO=$privateFlag
BLOCK_GUEST=$privateFlag
PROXY_PORT="4546"
TARGET_USER="$targetUser"
DB_PATH="$dbPath"
''';
    await File('$targetStaging/guard.conf').writeAsString(confContent, flush: true);

    final crxSrc = File(pkg.guardCrxPath ?? '$home/.local/share/chronos/guard/build/chronos.crx');
    if (crxSrc.existsSync()) {
      await crxSrc.copy('$targetStaging/chronos.crx');
      await Process.run('chmod', ['0644', '$targetStaging/chronos.crx']);
    }

    if (pkg.xpiPath != null && File(pkg.xpiPath!).existsSync()) {
      await File(pkg.xpiPath!).copy('$targetStaging/chronos.xpi');
      await Process.run('chmod', ['0644', '$targetStaging/chronos.xpi']);
    }

    if (pkg.caCertPath != null && File(pkg.caCertPath!).existsSync()) {
      await File(pkg.caCertPath!).copy('$targetStaging/chronos-proxy-ca.crt');
      await Process.run('chmod', ['0644', '$targetStaging/chronos-proxy-ca.crt']);
    }
    if (pkg.pacPath != null && File(pkg.pacPath!).existsSync()) {
      await File(pkg.pacPath!).copy('$targetStaging/proxy.pac');
      await Process.run('chmod', ['0644', '$targetStaging/proxy.pac']);
    }

    return targetStaging;
  }

  static Future<int> _runPkexecWithTimeout(List<String> args) async {
    try {
      final proc = await Process.start('pkexec', ['--disable-internal-agent', ...args]);
      final exitFuture = proc.exitCode;
      final code = await exitFuture.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );
      return code;
    } catch (_) {
      return -1;
    }
  }

  static const String familyDnsConf = '/usr/local/share/chronos/dns.conf';

  /// Family DNS currently applied by the guard: (provider or 'off', safeSearch).
  static ({String provider, bool safeSearch}) appliedFamilyDns() {
    try {
      final text = File(familyDnsConf).readAsStringSync();
      final provider = RegExp(r'DNS_PROVIDER="?([a-z]+)"?').firstMatch(text)?.group(1) ?? 'off';
      final safe = RegExp(r'SAFESEARCH=1').hasMatch(text);
      return (provider: provider, safeSearch: safe);
    } catch (_) {
      return (provider: 'off', safeSearch: false);
    }
  }

  static const String privateBrowsingConf = '/usr/local/share/chronos/private.conf';

  /// Block state currently applied by the guard (null when the guard never received a choice).
  static bool? appliedPrivateBrowsingBlock() {
    try {
      final m = RegExp(r'BLOCK_PRIVATE=([01])').firstMatch(File(privateBrowsingConf).readAsStringSync());
      return m == null ? null : m.group(1) == '1';
    } catch (_) {
      return null;
    }
  }

  /// Applies the incognito/guest block in all browsers through the root guard.
  /// Turning it on is passwordless; turning it off asks for the admin password and is
  /// refused by the guard while anti-cheat is active. Returns null on success.
  static Future<String?> applyPrivateBrowsingBlock(bool blocked) async {
    if (ChronosProfile.isDev) return ChronosProfile.devUnavailableMessage;
    if (!File(guardBinary).existsSync()) {
      return 'Chronos Guard não instalado: ative a proteção dos navegadores antes.';
    }
    if (appliedPrivateBrowsingBlock() == blocked) return null;
    // Guards installed before this option lack `set-incognito`: upgrade the guard (one
    // admin prompt). The new guard.conf already carries the saved choice.
    var hasCommand = false;
    try {
      final bin = File(guardBinary).readAsStringSync();
      hasCommand = bin.contains('cmd_set_incognito') && bin.contains('ProxyPacUrl');
    } catch (_) {}
    if (!hasCommand) {
      final up = await installViaPkexec();
      return up.success ? null : up.message;
    }
    try {
      final res = await Process.run('pkexec', [guardBinary, 'set-incognito', blocked ? '1' : '0']);
      if (res.exitCode == 0) return null;
      if (res.exitCode == 126) return 'Autorização cancelada.';
      final err = res.stderr.toString().trim();
      return err.isEmpty ? 'Falha ao aplicar (código ${res.exitCode}).' : err;
    } catch (e) {
      return 'Falha ao aplicar: $e';
    }
  }

  /// Parental mode: whether this account is an administrator (wheel/sudo/admin) and
  /// whether the guard already protects it (admin groups removed).
  static ({bool isAdmin, bool isProtected, String user}) accountProtectionStatus() {
    final user = Platform.environment['USER'] ?? '';
    var isAdmin = false;
    try {
      final groups = Process.runSync('id', ['-nG']).stdout.toString().split(RegExp(r'\s+'));
      isAdmin = groups.any((g) => g == 'wheel' || g == 'sudo' || g == 'admin');
    } catch (_) {}
    final isProtected = user.isNotEmpty && File('/var/lib/chronos/parental/$user.groups').existsSync();
    return (isAdmin: isAdmin, isProtected: isProtected, user: user);
  }

  /// Protects (or releases) this account through the guard; asks for an administrator's
  /// password (the guardian's). Returns null on success or an error message.
  static Future<String?> setAccountProtection(bool protect) async {
    if (ChronosProfile.isDev) return ChronosProfile.devUnavailableMessage;
    if (!File(guardBinary).existsSync()) return tr.guardNaoInstaladoAtiveAProtecao;
    final user = Platform.environment['USER'] ?? '';
    if (user.isEmpty) return 'USER?';
    try {
      final bin = File(guardBinary).readAsStringSync();
      if (!bin.contains('cmd_protect_account')) {
        final up = await installViaPkexec();
        if (!up.success) return up.message;
      }
    } catch (_) {}
    try {
      final res = await Process.run('pkexec', [guardBinary, 'protect-account', user, protect ? '1' : '0']);
      if (res.exitCode == 0) return null;
      if (res.exitCode == 126 || res.exitCode == 127) return tr.autorizacaoCancelada;
      final err = res.stderr.toString().trim().replaceFirst('chronos-guard: ', '');
      return err.isEmpty ? 'exit ${res.exitCode}' : err;
    } catch (e) {
      return '$e';
    }
  }

  /// Applies system-wide family DNS + browser SafeSearch policies through the root guard.
  /// Enabling/switching is passwordless (polkit); turning off asks for the admin password
  /// and is refused by the guard while anti-cheat is active.
  /// Returns null on success or an error message.
  static Future<String?> applyFamilyDns({required String provider, required bool safeSearch}) async {
    if (ChronosProfile.isDev) return ChronosProfile.devUnavailableMessage;
    if (!File(guardBinary).existsSync()) {
      return 'Chronos Guard não instalado: ative a proteção dos navegadores antes.';
    }
    final current = appliedFamilyDns();
    if (current.provider == provider && current.safeSearch == safeSearch) return null;
    try {
      final res = await Process.run('pkexec', [guardBinary, 'set-dns', provider, safeSearch ? '1' : '0']);
      if (res.exitCode == 0) return null;
      if (res.exitCode == 126) return 'Autorização cancelada.';
      final err = res.stderr.toString().trim();
      return err.isEmpty ? 'Falha ao aplicar o DNS família (código ${res.exitCode}).' : err;
    } catch (e) {
      return 'Falha ao aplicar o DNS família: $e';
    }
  }

  static String? _lastSignedXpiSeen;

  /// A newly Mozilla-signed XPI (scripts/sign-firefox.sh) is published to Firefox
  /// through the guard. One attempt per new file, so a failure never loops.
  static Future<void> syncNewSignedFirefoxXpi() async {
    if (ChronosProfile.isDev || !File(guardBinary).existsSync()) return;
    final home = Platform.environment['HOME'] ?? '';
    final signed = File('$home/.local/share/chronos/chronos-signed.xpi');
    if (!signed.existsSync()) return;
    final stamp = '${signed.lengthSync()}:${signed.lastModifiedSync().millisecondsSinceEpoch}';
    if (stamp == _lastSignedXpiSeen) return;
    _lastSignedXpiSeen = stamp;
    final sys = File('/usr/local/share/chronos/chronos.xpi');
    if (sys.existsSync() && sys.lengthSync() == signed.lengthSync()) return;
    await trySilentCrxUpdate();
  }

  /// Passwordlessly upgrades `/usr/local/share/chronos/chronos.crx` when permitted by polkit.
  static Future<bool> trySilentCrxUpdate() async {
    if (ChronosProfile.isDev) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    if (!File(guardBinary).existsSync()) return false;

    final pkg = await ExtensionPackager.packageAll();
    if (!pkg.success || pkg.guardCrxPath == null) return false;

    final confFile = File('/usr/local/share/chronos/guard.conf');
    final sysCrx = File('/usr/local/share/chronos/chronos.crx');
    final guardSrc = File(pkg.guardCrxPath!);
    bool crxUpToDate = false;
    if (confFile.existsSync() && sysCrx.existsSync() && guardSrc.existsSync()) {
      try {
        final conf = confFile.readAsStringSync();
        // The Firefox XPI is published with the CRX: a newly signed XPI alone must
        // also trigger update-crx.
        final sysXpi = File('/usr/local/share/chronos/chronos.xpi');
        final guardXpi = File('${guardSrc.parent.path}/chronos.xpi');
        final xpiUpToDate = !guardXpi.existsSync() ||
            (sysXpi.existsSync() && sysXpi.lengthSync() == guardXpi.lengthSync());
        if (conf.contains('VERSION="${pkg.version}"') &&
            sysCrx.lengthSync() == guardSrc.lengthSync() &&
            xpiUpToDate) {
          crxUpToDate = true;
        }
      } catch (_) {}
    }

    if (!crxUpToDate) {
      final code = await _runPkexecWithTimeout([
        guardBinary,
        'update-crx',
        pkg.guardCrxPath!,
        pkg.version,
      ]);
      if (code != 0) return false;
    }

    // Only attempt passwordless update-ca if the installed guard binary supports it.
    try {
      final binContent = File(guardBinary).readAsStringSync();
      if (binContent.contains('update-ca)') && pkg.caCertPath != null && pkg.pacPath != null) {
        final sysCa = File('/usr/local/share/chronos/chronos-proxy-ca.crt');
        final sysPac = File('/usr/local/share/chronos/proxy.pac');
        final userCa = File(pkg.caCertPath!);
        final needsCaSync = !sysCa.existsSync() ||
            !sysPac.existsSync() ||
            (userCa.existsSync() && sysCa.readAsStringSync() != userCa.readAsStringSync());
        if (needsCaSync) {
          await _runPkexecWithTimeout([
            guardBinary,
            'update-ca',
            pkg.caCertPath!,
            pkg.pacPath!,
          ]);
        }
      }
    } catch (_) {}

    return true;
  }

  /// Verifies Firefox Selective Proxy runtime health: CA cert sync, valid PAC target,
  /// and proxy listener availability on `127.0.0.1:4546`.
  static Future<({bool healthy, bool proxyReachable, bool caSynced, bool pacValid})>
      checkFirefoxProxyHealth({
    String? homeOverride,
    String? sysCaPathOverride,
    String? sysPacPathOverride,
    Future<bool> Function()? portProbe,
  }) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final sysCa = File(sysCaPathOverride ?? '/usr/local/share/chronos/chronos-proxy-ca.crt');
    final sysPac = File(sysPacPathOverride ?? '/usr/local/share/chronos/proxy.pac');
    final userCa = File('$home/.local/share/chronos/ca/chronos-proxy-ca.crt');

    bool caSynced = sysCa.existsSync();
    if (caSynced && userCa.existsSync()) {
      try {
        caSynced = sysCa.readAsStringSync() == userCa.readAsStringSync();
      } catch (_) {
        caSynced = false;
      }
    }

    bool pacValid = false;
    if (sysPac.existsSync()) {
      try {
        final pacContent = sysPac.readAsStringSync();
        pacValid = pacContent.contains('127.0.0.1:4546');
      } catch (_) {}
    }

    bool proxyReachable = false;
    if (portProbe != null) {
      proxyReachable = await portProbe();
    } else {
      try {
        final sock = await Socket.connect(
          '127.0.0.1',
          4546,
          timeout: const Duration(milliseconds: 250),
        );
        sock.destroy();
        proxyReachable = true;
      } catch (_) {
        proxyReachable = false;
      }
    }

    return (
      healthy: caSynced && pacValid && proxyReachable,
      proxyReachable: proxyReachable,
      caSynced: caSynced,
      pacValid: pacValid,
    );
  }

  static String getInstallCliCommand() {
    final user = Platform.environment['USER'] ?? 'dwu';
    return 'sudo $stagingDir/install-guard.sh $user $stagingDir';
  }

  static Future<bool> launchInstallerInTerminal() async {
    if (ChronosProfile.isDev) return false;
    await prepareStaging();
    final user = Platform.environment['USER'] ?? 'dwu';
    final shellCmd = '''
echo "=========================================================="
echo "  CHRONOS GUARD - Proteção Permanente & Proxy Focus"
echo "=========================================================="
echo "Configurando políticas de navegadores, CRX3, CA local e PAC..."
echo ""
sudo $stagingDir/install-guard.sh $user $stagingDir || pkexec $stagingDir/install-guard.sh $user $stagingDir
EXIT=\$?
echo ""
if [ "\$EXIT" -eq 0 ]; then
  echo "✅ Concluído com sucesso! Feche e reabra os navegadores se necessário."
else
  echo "❌ Falha (código \$EXIT). Execute manualmente: sudo $stagingDir/install-guard.sh"
fi
echo ""
read -rp "Pressione ENTER para fechar..."
''';

    final terminals = [
      'xdg-terminal-exec',
      'ghostty',
      'kitty',
      'alacritty',
      'foot',
      'gnome-terminal',
      'konsole',
      'xfce4-terminal',
      'xterm',
    ];

    for (final term in terminals) {
      final whichRes = await Process.run('which', [term]);
      if (whichRes.exitCode != 0) continue;

      try {
        if (term == 'gnome-terminal') {
          await Process.start(term, ['--', 'bash', '-c', shellCmd], mode: ProcessStartMode.detached);
        } else if (term == 'ghostty' || term == 'kitty' || term == 'alacritty' || term == 'xdg-terminal-exec') {
          await Process.start(term, ['-e', 'bash', '-c', shellCmd], mode: ProcessStartMode.detached);
        } else {
          await Process.start(term, ['-e', 'bash', '-c', shellCmd], mode: ProcessStartMode.detached);
        }
        return true;
      } catch (_) {}
    }

    return false;
  }

  static Future<bool> applyPoliciesIfInstalled() async {
    if (ChronosProfile.isDev) return false;
    if (!File(guardBinary).existsSync()) return false;
    try {
      await trySilentCrxUpdate();
      final res = await Process.run('pkexec', ['--disable-internal-agent', guardBinary, 'apply']);
      if (res.exitCode == 0) return true;
      final fallback = await Process.run('pkexec', [guardBinary, 'apply']);
      return fallback.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Stages Guard artifacts and requests 1-click graphical elevation (`pkexec`)
  /// to install/upgrade system-wide browser policies and `chronos-guard.service`.
  static Future<ActionFeedback> installViaPkexec({
    Future<ProcessResult> Function(String exe, List<String> args)? processRunner,
    String? stagingDirOverride,
    String? homeOverride,
    String? projectRootOverride,
    bool skipPrepareForTest = false,
  }) async {
    if (ChronosProfile.isDev) return const ActionFeedback(success: false, message: ChronosProfile.devUnavailableMessage);
    final targetStaging = skipPrepareForTest
        ? (stagingDirOverride ?? stagingDir)
        : await prepareStaging(
            stagingDirOverride: stagingDirOverride,
            homeOverride: homeOverride,
            projectRootOverride: projectRootOverride,
          );

    final installScript = File('$targetStaging/install-guard.sh');
    if (!installScript.existsSync()) {
      return const ActionFeedback(
        success: false,
        message: 'Script install-guard.sh não encontrado nos assets do Chronos.',
      );
    }

    final user = Platform.environment['USER'] ?? 'dwu';
    final runner = processRunner ?? Process.run;
    try {
      final res = await runner('pkexec', [
        'bash',
        installScript.path,
        user,
        targetStaging,
      ]);
      if (res.exitCode == 0) {
        return const ActionFeedback(
          success: true,
          message:
              'Chronos Guard instalado e políticas aplicadas em todos os navegadores!',
        );
      }
      final err = res.stderr.toString().trim();
      if (res.exitCode == 126) {
        return const ActionFeedback(
          success: false,
          message: 'Autenticação administrativa cancelada pelo usuário.',
        );
      }
      if (res.exitCode == 127) {
        return const ActionFeedback(
          success: false,
          message:
              'Agente gráfico do Polkit indisponível nesta sessão. Use o fallback manual no terminal.',
        );
      }
      return ActionFeedback(
        success: false,
        message: err.isNotEmpty
            ? 'Falha na instalação via pkexec: $err'
            : 'Falha ao instalar Guard (código ${res.exitCode}).',
      );
    } catch (e) {
      return ActionFeedback(
        success: false,
        message: 'Erro ao iniciar autenticação pkexec: $e',
      );
    }
  }

  /// Unified 1-click flow:
  /// 1. Packages bundled extensions/CA/PAC and prepares browser descriptors.
  /// 2. Ensures Chronos Guard policies are applied cleanly (silent update/apply when
  ///    already up-to-date, or 1-click Polkit elevation via `installViaPkexec` otherwise).
  /// 3. Reports any open Chromium-family browsers still awaiting user-confirmed restart.
  static Future<UnifiedBrowserSetupResult> installAndProtectAllBrowsers({
    bool isAntiCheatActive = false,
    String? homeOverride,
    Future<ProcessResult> Function(String exe, List<String> args)? pkexecRunner,
  }) async {
    final installReport = await BrowserExtensionInstaller.installAll(
      isAntiCheatActive: isAntiCheatActive,
      forceMandatory: true,
      homeOverride: homeOverride,
    );

    if (homeOverride != null) {
      final guard = await checkStatus();
      final pending = await BrowserExtensionInstaller.findOpenPendingChromiumBrowsers(
        homeOverride: homeOverride,
      );
      return UnifiedBrowserSetupResult(
        success: installReport.success,
        message: installReport.message,
        installReport: installReport,
        guardStatus: guard,
        openPendingChromiumBrowsers: pending,
      );
    }

    var guard = await checkStatus();
    var guardMsg = '';
    var guardOk = guard.isFullyActive;
    var polkitBlocked = false;

    if (guard.isInstalled && !guard.isGuardOutdated) {
      final applied = await applyPoliciesIfInstalled();
      if (applied) {
        guardOk = true;
      } else {
        final fb = await installViaPkexec(processRunner: pkexecRunner);
        guardOk = fb.success;
        guardMsg = fb.message;
        polkitBlocked = !fb.success && guardMsg.contains('Polkit');
      }
    } else {
      final fb = await installViaPkexec(processRunner: pkexecRunner);
      guardOk = fb.success;
      guardMsg = fb.message;
      polkitBlocked = !fb.success &&
          (guardMsg.contains('Polkit') || guardMsg.contains('cancelada'));
    }

    guard = await checkStatus();
    final pendingOpen =
        await BrowserExtensionInstaller.findOpenPendingChromiumBrowsers();

    final summary = guardOk
        ? (pendingOpen.isEmpty
            ? 'Navegadores configurados e proteção Guard aplicada com sucesso!'
            : 'Políticas aplicadas! Confirme o reinício para ${pendingOpen.map((b) => b.name).join(', ')}.')
        : (guardMsg.isNotEmpty ? guardMsg : installReport.message);

    return UnifiedBrowserSetupResult(
      success: installReport.success && guardOk,
      message: summary,
      installReport: installReport,
      guardStatus: guard,
      openPendingChromiumBrowsers: pendingOpen,
      polkitUnavailableOrCancelled: polkitBlocked,
    );
  }

  /// Verifies Anti-Burla is inactive before removing system-level browser policies via `chronos-guard uninstall`
  /// and cleaning user-level browser extension descriptors/profiles.
  static Future<ActionFeedback> verifyAntiCheatAndUninstall({
    Future<AntiCheatStateDto> Function()? antiCheatProvider,
    Future<ProcessResult> Function(String exe, List<String> args)? processRunner,
    bool? guardInstalledOverride,
    String? homeOverride,
  }) async {
    if (ChronosProfile.isDev) return const ActionFeedback(success: true, message: ChronosProfile.devUnavailableMessage);
    final ac = await (antiCheatProvider ?? getAntiCheatState)();
    if (ac.isActive) {
      return ActionFeedback(
        success: false,
        message: ac.mode == 'NUKE'
            ? 'Remoção bloqueada: Modo Nuke ativo. Aguarde o tempo expirar.'
            : 'Remoção bloqueada: Anti-Burla ativo. Conclua o desafio antes de remover.',
      );
    }

    final hasGuard = guardInstalledOverride ?? File(guardBinary).existsSync();
    if (!hasGuard) {
      await BrowserExtensionInstaller.removeExtensionFromUserBrowsers(
        homeOverride: homeOverride,
      );
      return const ActionFeedback(
        success: true,
        message: 'Nenhum Guard de sistema instalado; limpeza de perfil concluída.',
      );
    }

    final runner = processRunner ?? Process.run;
    try {
      var res = await runner('pkexec', ['--disable-internal-agent', guardBinary, 'uninstall']);
      if (res.exitCode != 0 && processRunner == null) {
        res = await runner('pkexec', [guardBinary, 'uninstall']);
      }
      if (res.exitCode == 0) {
        await BrowserExtensionInstaller.removeExtensionFromUserBrowsers(
          homeOverride: homeOverride,
        );
        return const ActionFeedback(
          success: true,
          message: 'Chronos Guard e políticas dos navegadores removidos com sucesso.',
        );
      }
      final err = res.stderr.toString().trim();
      return ActionFeedback(
        success: false,
        message: err.isNotEmpty
            ? 'Falha ao remover Guard: $err'
            : 'Autenticação administrativa cancelada (código ${res.exitCode}).',
      );
    } catch (e) {
      return ActionFeedback(
        success: false,
        message: 'Erro ao executar desinstalação do Guard: $e',
      );
    }
  }
}
