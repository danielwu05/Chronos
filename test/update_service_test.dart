import 'dart:convert';
import 'dart:io';

import 'package:chronos_app/services/update_service.dart';
import 'package:chronos_app/src/rust/api/updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake GitHub: /repos/o/r/releases/latest + asset downloads.
class _FakeGithub {
  late HttpServer server;
  Map<String, dynamic> release = {};
  final Map<String, List<int>> files = {};

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/repos/o/r/releases/latest') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(release));
      } else if (files.containsKey(path)) {
        req.response.add(files[path]!);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  }

  void publish({required String tag, required String archiveName, bool prerelease = false}) {
    release = {
      'tag_name': tag,
      'draft': false,
      'prerelease': prerelease,
      'body': 'notas',
      'assets': [
        for (final name in [archiveName, 'latest.json', 'latest.json.sig'])
          {'name': name, 'browser_download_url': '$base/dl/$name'},
      ],
    };
  }
}

int _cmp(String a, String b) {
  List<int> k(String v) => v.split(RegExp(r'[-+]')).first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final x = k(a), y = k(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

void main() {
  late Directory tmp;
  late _FakeGithub gh;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chronos_update_test_');
    gh = _FakeGithub();
    await gh.start();
  });

  tearDown(() async {
    await gh.server.close(force: true);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Builds a release tar.gz shaped like the Flutter bundle.
  Future<List<int>> buildArchive({bool complete = true}) async {
    final bundle = Directory('${tmp.path}/bundle_src')..createSync(recursive: true);
    File('${bundle.path}/chronos_app').writeAsStringSync('#!/bin/sh\n');
    if (complete) File('${bundle.path}/chronos_proxy').writeAsStringSync('bin');
    File('${bundle.path}/data/chronos_assets/chronos_extension/manifest.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    final out = '${tmp.path}/pkg.tar.gz';
    final r = await Process.run('tar', ['-czf', out, '-C', bundle.path, '.']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    bundle.deleteSync(recursive: true);
    return File(out).readAsBytesSync();
  }

  UpdateService makeService({
    required String sha,
    String current = '1.0.0',
    bool signatureValid = true,
    String manifestVersion = '1.1.0',
  }) {
    return UpdateService(
      apiBase: gh.base,
      repository: 'o/r',
      currentVersionOverride: current,
      installRootOverride: '${tmp.path}/app',
      guardBinaryPath: '${tmp.path}/no-guard',
      comparer: _cmp,
      hasher: (p) async => p.endsWith('.tar.gz') ? sha : 'x',
      verifier: (bytes, sig) async {
        if (!signatureValid || sig != 'SIG') throw 'Assinatura da atualização inválida';
        final m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final a = (m['assets'] as Map)['linux-x64'] as Map;
        return ReleaseManifestDto(
          version: m['version'] as String,
          publishedAt: '',
          notes: 'Novidades',
          guardSha256: '',
          assets: [
            ReleaseAssetDto(platform: 'linux-x64', name: a['name'] as String, sha256: a['sha256'] as String, size: a['size'] as int),
          ],
        );
      },
    )..toString();
  }

  void serveRelease(List<int> archive, {String version = '1.1.0', String sha = 'abc', bool prerelease = false}) {
    final name = 'chronos-linux-x64-$version.tar.gz';
    gh.files['/dl/$name'] = archive;
    gh.files['/dl/latest.json'] = utf8.encode(jsonEncode({
      'version': version,
      'assets': {
        'linux-x64': {'name': name, 'sha256': sha, 'size': archive.length},
      },
    }));
    gh.files['/dl/latest.json.sig'] = utf8.encode('SIG\n');
    gh.publish(tag: 'v$version', archiveName: name, prerelease: prerelease);
  }

  test('detects a newer signed release and installs it atomically', () async {
    final archive = await buildArchive();
    serveRelease(archive);
    final service = makeService(sha: 'abc');

    final info = await service.checkForUpdate();
    expect(info, isNotNull);
    expect(info!.version, '1.1.0');
    expect(info.notes, 'Novidades');

    final stages = <UpdateStage>[];
    final exe = await service.downloadAndInstall(info, (s, _) => stages.add(s));
    expect(exe, '${tmp.path}/app/current/chronos_app');
    expect(Link('${tmp.path}/app/current').targetSync(), 'versions/1.1.0');
    expect(File('${tmp.path}/app/current/chronos_proxy').existsSync(), isTrue);
    expect(stages, containsAllInOrder([UpdateStage.downloading, UpdateStage.verifying, UpdateStage.installing]));
    expect(Directory('${tmp.path}/app/.download').listSync(), isEmpty);
  });

  test('no update when same version, pre-release, or bad signature', () async {
    final archive = await buildArchive();
    serveRelease(archive);
    expect(await makeService(sha: 'abc', current: '1.1.0').checkForUpdate(), isNull);
    expect(await makeService(sha: 'abc', signatureValid: false).checkForUpdate(), isNull);
    serveRelease(archive, prerelease: true);
    expect(await makeService(sha: 'abc').checkForUpdate(), isNull);
  });

  test('sha mismatch or incomplete package never moves current', () async {
    final good = await buildArchive();
    serveRelease(good);
    final service = makeService(sha: 'abc');
    final info = (await service.checkForUpdate())!;
    await service.downloadAndInstall(info, (_, _) {});
    expect(Link('${tmp.path}/app/current').targetSync(), 'versions/1.1.0');

    // Wrong hash for 1.2.0
    serveRelease(good, version: '1.2.0', sha: 'expected');
    final svc2 = makeService(sha: 'actual-different', current: '1.1.0');
    final info2 = await svc2.checkForUpdate();
    expect(info2, isNotNull);
    await expectLater(svc2.downloadAndInstall(info2!, (_, _) {}), throwsA(isA<StateError>()));
    expect(Link('${tmp.path}/app/current').targetSync(), 'versions/1.1.0');

    // Incomplete archive (no chronos_proxy) for 1.3.0
    final broken = await buildArchive(complete: false);
    serveRelease(broken, version: '1.3.0', sha: 'abc');
    final svc3 = makeService(sha: 'abc', current: '1.1.0');
    final info3 = (await svc3.checkForUpdate())!;
    await expectLater(svc3.downloadAndInstall(info3, (_, _) {}), throwsA(isA<StateError>()));
    expect(Link('${tmp.path}/app/current').targetSync(), 'versions/1.1.0');
    expect(Directory('${tmp.path}/app/versions/1.3.0').existsSync(), isFalse);
  });

  test('keeps only the two newest versions', () async {
    for (final v in ['1.1.0', '1.2.0', '1.3.0']) {
      serveRelease(await buildArchive(), version: v);
      final svc = makeService(sha: 'abc', current: '1.0.0');
      await svc.downloadAndInstall((await svc.checkForUpdate())!, (_, _) {});
    }
    final names = Directory('${tmp.path}/app/versions')
        .listSync()
        .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();
    expect(names, {'1.2.0', '1.3.0'});
    expect(Link('${tmp.path}/app/current').targetSync(), 'versions/1.3.0');
  });
}
