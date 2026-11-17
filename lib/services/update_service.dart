import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../src/rust/api/updater.dart';
import 'app_version.dart';
import 'chronos_guard_service.dart';

/// A newer, signature-verified release that can be installed.
class UpdateInfo {
  final String version;
  final String notes;
  final String archiveName;
  final String archiveUrl;
  final String archiveSha256;
  final int archiveSize;
  final String guardSha256;

  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.archiveName,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.archiveSize,
    required this.guardSha256,
  });
}

enum UpdateStage { downloading, verifying, installing, guard, restarting }

typedef UpdateProgress = void Function(UpdateStage stage, double? fraction);
typedef ManifestVerifier = Future<ReleaseManifestDto> Function(List<int> manifest, String signatureB64);
typedef FileHasher = Future<String> Function(String path);
typedef VersionComparer = int Function(String a, String b);

/// Checks GitHub Releases for signed Chronos updates and installs them into
/// `~/.local/share/chronos/app/versions/X.Y.Z`, switching the `current` symlink atomically.
class UpdateService {
  static const String platformKey = 'linux-x64';
  static const String manifestAssetName = 'latest.json';
  static const String signatureAssetName = 'latest.json.sig';
  static const int keepVersions = 2;

  final String apiBase;
  final String repository;
  final String currentVersion;
  final String installRoot;
  final String guardBinaryPath;
  final ManifestVerifier verifyManifest;
  final FileHasher hashFile;
  final VersionComparer compare;
  final Duration timeout;

  UpdateService({
    this.apiBase = 'https://api.github.com',
    this.repository = updateRepository,
    String? currentVersionOverride,
    String? installRootOverride,
    this.guardBinaryPath = ChronosGuardService.guardBinary,
    ManifestVerifier? verifier,
    FileHasher? hasher,
    VersionComparer? comparer,
    this.timeout = const Duration(seconds: 8),
  })  : currentVersion = currentVersionOverride ?? appVersion,
        installRoot = installRootOverride ?? installRootFor(),
        verifyManifest = verifier ??
            ((m, s) => verifyReleaseManifest(manifestJson: m, signatureB64: s)),
        hashFile = hasher ?? ((p) => sha256File(path: p)),
        compare = comparer ?? ((a, b) => compareVersions(a: a, b: b));

  HttpClient _client() => HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'Chronos-Updater/$currentVersion';

  Future<List<int>> _getBytes(String url, {Map<String, String>? headers}) async {
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      headers?.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode} em $url');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  /// Returns the newest stable, signature-verified release when it is newer than
  /// [currentVersion]; `null` when up to date, offline, or the release is invalid.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final body = await _getBytes(
        '$apiBase/repos/$repository/releases/latest',
        headers: {'Accept': 'application/vnd.github+json'},
      );
      final release = jsonDecode(utf8.decode(body));
      if (release is! Map || release['draft'] == true || release['prerelease'] == true) return null;

      final assets = (release['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => MapEntry(a['name']?.toString() ?? '', a['browser_download_url']?.toString() ?? ''))
          .where((e) => e.key.isNotEmpty && e.value.isNotEmpty);
      final urls = Map<String, String>.fromEntries(assets);
      final manifestUrl = urls[manifestAssetName];
      final sigUrl = urls[signatureAssetName];
      if (manifestUrl == null || sigUrl == null) return null;

      final manifestBytes = await _getBytes(manifestUrl);
      final signature = utf8.decode(await _getBytes(sigUrl)).trim();
      final manifest = await verifyManifest(manifestBytes, signature);

      final tag = (release['tag_name']?.toString() ?? '').replaceFirst(RegExp(r'^v'), '');
      if (tag.isNotEmpty && compare(tag, manifest.version) != 0) return null;
      if (compare(manifest.version, currentVersion) <= 0) return null;

      final asset = manifest.assets.where((a) => a.platform == platformKey).firstOrNull;
      if (asset == null) return null;
      final archiveUrl = urls[asset.name];
      if (archiveUrl == null) return null;

      return UpdateInfo(
        version: manifest.version,
        notes: manifest.notes.isNotEmpty ? manifest.notes : (release['body']?.toString() ?? ''),
        archiveName: asset.name,
        archiveUrl: archiveUrl,
        archiveSha256: asset.sha256,
        archiveSize: asset.size.toInt(),
        guardSha256: manifest.guardSha256,
      );
    } catch (_) {
      return null;
    }
  }

  String get currentLinkPath => '$installRoot/current';
  String versionDir(String version) => '$installRoot/versions/$version';

  Future<String> _download(UpdateInfo info, UpdateProgress onProgress) async {
    final dlDir = Directory('$installRoot/.download');
    await dlDir.create(recursive: true);
    final target = File('${dlDir.path}/${info.archiveName}');
    final part = File('${target.path}.part');
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse(info.archiveUrl)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('Falha ao baixar a atualização (HTTP ${res.statusCode})');
      }
      final total = info.archiveSize > 0 ? info.archiveSize : res.contentLength;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(UpdateStage.downloading, total > 0 ? (received / total).clamp(0, 1).toDouble() : null);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
    if (target.existsSync()) target.deleteSync();
    part.renameSync(target.path);
    return target.path;
  }

  /// Downloads, verifies and activates [info]. Throws on any failure; the `current`
  /// symlink only moves after the new version is fully extracted and validated.
  /// Returns the path of the new `chronos_app` executable.
  Future<String> downloadAndInstall(UpdateInfo info, UpdateProgress onProgress) async {
    onProgress(UpdateStage.downloading, 0);
    final archive = await _download(info, onProgress);

    onProgress(UpdateStage.verifying, null);
    final digest = (await hashFile(archive)).toLowerCase();
    if (digest != info.archiveSha256.toLowerCase()) {
      File(archive).deleteSync();
      throw StateError('O pacote baixado não confere com a assinatura da release (SHA-256).');
    }

    onProgress(UpdateStage.installing, null);
    final finalDir = Directory(versionDir(info.version));
    final staging = Directory('${finalDir.path}.tmp');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    await staging.create(recursive: true);
    final tar = await Process.run('tar', ['-xzf', archive, '-C', staging.path]);
    if (tar.exitCode != 0) {
      staging.deleteSync(recursive: true);
      throw StateError('Falha ao extrair a atualização: ${tar.stderr}');
    }
    for (final required in ['chronos_app', 'chronos_proxy', 'data/chronos_assets/chronos_extension/manifest.json']) {
      if (!File('${staging.path}/$required').existsSync()) {
        staging.deleteSync(recursive: true);
        throw StateError('Pacote incompleto: falta $required');
      }
    }
    if (finalDir.existsSync()) finalDir.deleteSync(recursive: true);
    staging.renameSync(finalDir.path);

    // Atomic switch: create a fresh symlink beside `current`, then rename over it.
    final tmpLink = Link('$currentLinkPath.new');
    if (tmpLink.existsSync()) tmpLink.deleteSync();
    tmpLink.createSync('versions/${info.version}');
    tmpLink.renameSync(currentLinkPath);

    try {
      File(archive).deleteSync();
    } catch (_) {}
    _pruneOldVersions(keep: info.version);
    return '$currentLinkPath/chronos_app';
  }

  void _pruneOldVersions({required String keep}) {
    final versionsDir = Directory('$installRoot/versions');
    if (!versionsDir.existsSync()) return;
    final dirs = versionsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => !d.path.endsWith('.tmp'))
        .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toList()
      ..sort((a, b) => compare(b, a));
    final keepSet = <String>{keep, ...dirs.take(keepVersions)};
    for (final name in dirs) {
      if (!keepSet.contains(name)) {
        try {
          Directory('${versionsDir.path}/$name').deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// True when the installed root guard differs from the one shipped in [info].
  Future<bool> guardNeedsUpdate(UpdateInfo info) async {
    if (info.guardSha256.isEmpty || !File(guardBinaryPath).existsSync()) return false;
    try {
      return (await hashFile(guardBinaryPath)).toLowerCase() != info.guardSha256.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  /// Reinstalls the root guard from the newly installed version (asks for the admin
  /// password via pkexec). Returns false when the user cancels or it fails.
  Future<bool> updateGuardFrom(UpdateInfo info) async {
    final assets = '${versionDir(info.version)}/data/chronos_assets';
    final res = await ChronosGuardService.installViaPkexec(projectRootOverride: assets);
    return res.success;
  }

  /// Starts the new version detached and exits this process.
  static Future<Never> relaunch(String executable) async {
    await Process.start(executable, const [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
