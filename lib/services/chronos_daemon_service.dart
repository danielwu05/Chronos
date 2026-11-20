import 'dart:convert';
import 'dart:io';

import 'app_profile.dart';
import 'app_version.dart';
import 'package:chronos_app/services/extension_packager.dart';

/// Manages the persistent background `chronos_proxy` daemon (`127.0.0.1:4545` + `4546`)
/// via `systemd --user` so Firefox proxy filtering, Chrome extension sync, and `/blocked`
/// continue operating seamlessly even when the Flutter GUI window is closed.
class ChronosDaemonService {
  static String get serviceName => ChronosProfile.daemonServiceName;

  static String? findPackagedProxyBinary() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Installed releases always ship their matching daemon next to the app binary.
    if (isRunningFromInstallRoot()) {
      final bundled = File('$exeDir/chronos_proxy');
      if (bundled.existsSync() && bundled.lengthSync() > 0) return bundled.path;
    }
    final root = ExtensionPackager.findProjectRoot();
    final home = Platform.environment['HOME'] ?? '/tmp';

    final buildCandidates = <String>[
      '$exeDir/chronos_proxy',
      if (root != null) '$root/rust/target/release/chronos_proxy',
      if (root != null) '$root/rust/target/debug/chronos_proxy',
    ];
    File? newest;
    DateTime? newestMtime;
    for (final path in buildCandidates) {
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() <= 0) continue;
      final mtime = f.lastModifiedSync();
      if (newest == null || newestMtime == null || mtime.isAfter(newestMtime)) {
        newest = f;
        newestMtime = mtime;
      }
    }
    if (newest != null) {
      return newest.path;
    }

    final installed = File('$home/.local/share/${ChronosProfile.dataDirName}/bin/chronos_proxy');
    if (installed.existsSync() && installed.lengthSync() > 0) {
      return installed.path;
    }
    return null;
  }

  /// Checks whether the local Chronos HTTP API daemon (`127.0.0.1:4545`) responds cleanly.
  static Future<bool> isApiDaemonHealthy({int? port}) async {
    final p = port ?? ChronosProfile.apiPort;
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);
    try {
      final req = await client
          .get('127.0.0.1', p, '/api/ping')
          .timeout(const Duration(milliseconds: 500));
      final res = await req.close().timeout(const Duration(milliseconds: 500));
      if (res.statusCode != 200) return false;
      final body = await utf8.decoder.bind(res).join().timeout(const Duration(milliseconds: 500));
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['pong'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _areFilesIdentical(File a, File b) async {
    if (!a.existsSync() || !b.existsSync()) return false;
    if (a.lengthSync() != b.lengthSync()) return false;
    final bytesA = await a.readAsBytes();
    final bytesB = await b.readAsBytes();
    if (bytesA.length != bytesB.length) return false;
    for (int i = 0; i < bytesA.length; i++) {
      if (bytesA[i] != bytesB[i]) return false;
    }
    return true;
  }

  /// Copies the image AI model (same as the extension's) next to the daemon, which
  /// uses it for the whole-screen +18 detector.
  static void _installNsfwModel(String home) {
    try {
      final root = ExtensionPackager.findProjectRoot();
      if (root == null) return;
      final src = Directory('$root/chronos_extension/vendor/nsfw_model');
      if (!src.existsSync()) return;
      final dst = Directory('$home/.local/share/${ChronosProfile.dataDirName}/model');
      dst.createSync(recursive: true);
      for (final f in src.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        final out = File('${dst.path}/$name');
        if (out.existsSync() && out.lengthSync() == f.lengthSync()) continue;
        f.copySync('${out.path}.tmp');
        File('${out.path}.tmp').renameSync(out.path);
      }
    } catch (_) {}
  }

  /// Ensures `chronos_proxy` is installed under `~/.local/share/chronos/bin/` and running
  /// as a persistent `systemd --user` service (with detached process fallback).
  static Future<bool> ensureBackgroundDaemonRunning({
    required String dbPath,
    String? homeOverride,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }

    final srcPath = findPackagedProxyBinary();
    if (srcPath == null) {
      return await isApiDaemonHealthy();
    }

    final home = homeOverride ?? Platform.environment['HOME'] ?? '/tmp';
    _installNsfwModel(home);
    final binDir = Directory('$home/.local/share/${ChronosProfile.dataDirName}/bin');
    final installedBin = File('${binDir.path}/chronos_proxy');
    final caDir = '$home/.local/share/chronos/ca';
    await binDir.create(recursive: true);

    bool binaryUpdated = false;
    final srcFile = File(srcPath);
    if (srcFile.path != installedBin.path) {
      final identical = await _areFilesIdentical(srcFile, installedBin);
      if (!identical) {
        final tmpBin = File('${installedBin.path}.tmp.$pid');
        await srcFile.copy(tmpBin.path);
        await Process.run('chmod', ['0755', tmpBin.path]);
        await tmpBin.rename(installedBin.path);
        binaryUpdated = true;
      }
    }

    final unitDir = Directory('$home/.config/systemd/user');
    await unitDir.create(recursive: true);
    final unitFile = File('${unitDir.path}/$serviceName');
    final desiredUnit = '''[Unit]
Description=Chronos Focus Filtering Proxy & Local API Daemon
After=default.target

[Service]
Type=simple
ExecStart=${installedBin.path} --db $dbPath --ca-dir $caDir
${ChronosProfile.isDev ? 'Environment=CHRONOS_PROFILE=dev\n' : ''}Restart=always
RestartSec=1

[Install]
WantedBy=default.target
''';

    bool unitChanged = !unitFile.existsSync() || unitFile.readAsStringSync() != desiredUnit;
    if (unitChanged) {
      await unitFile.writeAsString(desiredUnit, flush: true);
    }

    try {
      final systemctlCheck = await Process.run('systemctl', ['--user', 'is-active', serviceName]);
      final isActive = systemctlCheck.exitCode == 0 &&
          systemctlCheck.stdout.toString().trim() == 'active';

      if (unitChanged) {
        await Process.run('systemctl', ['--user', 'daemon-reload']);
      }
      if (!isActive) {
        // Dev daemon runs only while developing: started, never enabled at login.
        await Process.run('systemctl', ['--user', ChronosProfile.isDev ? 'start' : 'enable', if (!ChronosProfile.isDev) '--now', serviceName]);
      } else if (binaryUpdated || unitChanged) {
        await Process.run('systemctl', ['--user', 'restart', serviceName]);
      }

      for (int i = 0; i < 15; i++) {
        if (await isApiDaemonHealthy()) return true;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}

    // Fallback when systemd user session isn't active: spawn detached if port 4545 is free.
    if (!await isApiDaemonHealthy()) {
      try {
        await Process.start(
          installedBin.path,
          ['--db', dbPath, '--ca-dir', caDir],
          environment: ChronosProfile.isDev ? {'CHRONOS_PROFILE': 'dev'} : null,
          mode: ProcessStartMode.detached,
        );
        for (int i = 0; i < 15; i++) {
          if (await isApiDaemonHealthy()) return true;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (_) {}
    }

    return await isApiDaemonHealthy();
  }
}
