import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chronos_app/services/web_block_server.dart';

/// Result returned by [ExtensionPackager.packageAll].
class PackagingResult {
  final bool success;
  final String version;
  final String extensionId;
  final String? crxPath;
  final String? guardCrxPath;
  final String? xpiPath;
  final String? caCertPath;
  final String? pacPath;
  final String message;

  const PackagingResult({
    required this.success,
    required this.version,
    required this.extensionId,
    this.crxPath,
    this.guardCrxPath,
    this.xpiPath,
    this.caCertPath,
    this.pacPath,
    required this.message,
  });
}

/// Deterministic packager for Chromium CRX3 (`chronos_extension.pem`-signed),
/// Firefox XPI, local Root CA fallback, and fail-open proxy PAC assets.
class ExtensionPackager {
  static const String defaultChromeExtensionId = 'jmbcpjljbgjabggbblfajojeahficjgi';
  static const String firefoxAddonId = 'chronos-focus@chronos.local';

  /// Finds the workspace/project root or bundled `<exe>/data/chronos_assets`
  /// directory holding `chronos_extension/manifest.json`.
  static String? findProjectRoot({
    String? overrideRoot,
    String? executablePathOverride,
  }) {
    final exeDir =
        File(executablePathOverride ?? Platform.resolvedExecutable).parent.path;
    final bundledAssets = '$exeDir/data/chronos_assets';
    final candidates = <String>[
      if (overrideRoot != null && overrideRoot.isNotEmpty) overrideRoot,
      if (executablePathOverride != null &&
          executablePathOverride.isNotEmpty) ...[
        bundledAssets,
        exeDir,
        Directory(exeDir).parent.path,
      ],
      Directory.current.path,
      if (executablePathOverride == null || executablePathOverride.isEmpty) ...[
        bundledAssets,
        exeDir,
        Directory(exeDir).parent.path,
      ],
      '${Directory.current.path}/chronos_app',
    ];

    for (final base in candidates) {
      var cur = Directory(base);
      for (int depth = 0; depth < 6; depth++) {
        if (File('${cur.path}/chronos_extension/manifest.json').existsSync()) {
          return cur.path;
        }
        final parent = cur.parent;
        if (parent.path == cur.path) break;
        cur = parent;
      }
    }
    return null;
  }

  /// Derives the 32-char Chrome Extension ID from a 32-byte SHA-256 public key digest.
  static String extensionIdFromSpkiSha256(Uint8List sha256Digest) {
    final buf = StringBuffer();
    for (int i = 0; i < 16 && i < sha256Digest.length; i++) {
      final b = sha256Digest[i];
      buf.writeCharCode(0x61 + ((b >> 4) & 0x0f));
      buf.writeCharCode(0x61 + (b & 0x0f));
    }
    return buf.toString();
  }

  /// Compares dotted semantic versions like `1.1.0` vs `1.0.2`.
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static String bumpPatchVersion(String v) {
    final parts = v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    parts[2] = parts[2] + 1;
    return parts.sublist(0, 3).join('.');
  }

  /// Encodes an unsigned protobuf varint cleanly.
  static Uint8List encodeVarint(int value) {
    final out = BytesBuilder(copy: false);
    var v = value;
    do {
      int byte = v & 0x7f;
      v >>>= 7;
      if (v != 0) byte |= 0x80;
      out.addByte(byte);
    } while (v != 0);
    return out.toBytes();
  }

  static Uint8List encodeProtoBytesField(int fieldNumber, Uint8List payload) {
    final out = BytesBuilder(copy: false);
    out.add(encodeVarint((fieldNumber << 3) | 2));
    out.add(encodeVarint(payload.length));
    out.add(payload);
    return out.toBytes();
  }

  static Uint8List uint32Le(int value) {
    final bd = ByteData(4)..setUint32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  /// Builds a Chrome-spec CRX3 archive from [zipBytes] signed with RSA [pemPath].
  static Future<({Uint8List crxBytes, String extensionId})> buildCrx3Bytes({
    required Uint8List zipBytes,
    required String pemPath,
  }) async {
    final tmpDir = await Directory.systemTemp.createTemp('chronos_crx3_');
    try {
      final spkiFile = File('${tmpDir.path}/pub.der');
      final pubRes = await Process.run('openssl', [
        'pkey',
        '-in',
        pemPath,
        '-pubout',
        '-outform',
        'DER',
        '-out',
        spkiFile.path,
      ]);
      if (pubRes.exitCode != 0 || !spkiFile.existsSync()) {
        throw ProcessException(
          'openssl',
          ['pkey', '-pubout'],
          'Failed extracting SPKI DER: ${pubRes.stderr}',
          pubRes.exitCode,
        );
      }
      final spkiDer = await spkiFile.readAsBytes();

      final dgstFile = File('${tmpDir.path}/spki.sha256');
      final hashRes = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-binary',
        '-out',
        dgstFile.path,
        spkiFile.path,
      ]);
      if (hashRes.exitCode != 0 || !dgstFile.existsSync()) {
        throw ProcessException(
          'openssl',
          ['dgst', '-sha256'],
          'Failed hashing SPKI DER: ${hashRes.stderr}',
          hashRes.exitCode,
        );
      }
      final spkiHash = await dgstFile.readAsBytes();
      final crxId = Uint8List.fromList(spkiHash.sublist(0, 16));
      final extensionId = extensionIdFromSpkiSha256(spkiHash);

      // SignedData { optional bytes crx_id = 1; }
      final signedData = encodeProtoBytesField(1, crxId);

      // Sign `"CRX3 SignedData\x00" + le32(signedData.length) + signedData + zipBytes`
      final signInputFile = File('${tmpDir.path}/to_sign.bin');
      final signBuilder = BytesBuilder(copy: false)
        ..add(ascii.encode('CRX3 SignedData'))
        ..addByte(0)
        ..add(uint32Le(signedData.length))
        ..add(signedData)
        ..add(zipBytes);
      await signInputFile.writeAsBytes(signBuilder.toBytes(), flush: true);

      final sigFile = File('${tmpDir.path}/sig.bin');
      final signRes = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-sign',
        pemPath,
        '-out',
        sigFile.path,
        signInputFile.path,
      ]);
      if (signRes.exitCode != 0 || !sigFile.existsSync()) {
        throw ProcessException(
          'openssl',
          ['dgst', '-sign'],
          'Failed signing CRX3 payload: ${signRes.stderr}',
          signRes.exitCode,
        );
      }
      final signature = await sigFile.readAsBytes();

      // AsymmetricKeyProof { public_key = 1; signature = 2; }
      final proof = BytesBuilder(copy: false)
        ..add(encodeProtoBytesField(1, spkiDer))
        ..add(encodeProtoBytesField(2, signature));

      // CrxFileHeader { sha256_with_rsa = 2; signed_header_data = 10000; }
      final crxHeader = (BytesBuilder(copy: false)
            ..add(encodeProtoBytesField(2, proof.toBytes()))
            ..add(encodeProtoBytesField(10000, signedData)))
          .toBytes();

      final out = BytesBuilder(copy: false)
        ..add(ascii.encode('Cr24'))
        ..add(uint32Le(3))
        ..add(uint32Le(crxHeader.length))
        ..add(crxHeader)
        ..add(zipBytes);

      return (crxBytes: out.toBytes(), extensionId: extensionId);
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Ensures `~/.local/share/chronos/ca/chronos-proxy-ca.{crt,key}` and `proxy.pac` exist.
  static Future<({String? caCertPath, String? pacPath})> ensureProxyCaAndPac({
    String? homeDirOverride,
  }) async {
    final home = homeDirOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final chronosDir = Directory('$home/.local/share/chronos');
    final caDir = Directory('${chronosDir.path}/ca');
    await caDir.create(recursive: true);

    final caCertFile = File('${caDir.path}/chronos-proxy-ca.crt');
    final caKeyFile = File('${caDir.path}/chronos-proxy-ca.key');

    if (!caCertFile.existsSync() || !caKeyFile.existsSync()) {
      final res = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        caKeyFile.path,
        '-out',
        caCertFile.path,
        '-days',
        '3650',
        '-subj',
        '/O=Chronos Focus/CN=Chronos Local Focus CA',
        '-addext',
        'basicConstraints=critical,CA:TRUE,pathlen:0',
        '-addext',
        'keyUsage=critical,keyCertSign,cRLSign',
        '-addext',
        'subjectKeyIdentifier=hash',
      ]);
      if (res.exitCode == 0) {
        await Process.run('chmod', ['0600', caKeyFile.path]);
        await Process.run('chmod', ['0644', caCertFile.path]);
      }
    }

    final pacContent = WebBlockServer.buildProxyPacContent();
    final pacFile = File('${chronosDir.path}/proxy.pac');
    await pacFile.writeAsString(pacContent, flush: true);
    await Process.run('chmod', ['0644', pacFile.path]);
    final caPacFile = File('${caDir.path}/proxy.pac');
    await caPacFile.writeAsString(pacContent, flush: true);
    await Process.run('chmod', ['0644', caPacFile.path]);

    return (
      caCertPath: caCertFile.existsSync() ? caCertFile.path : null,
      pacPath: pacFile.existsSync() ? pacFile.path : null,
    );
  }

  /// Computes a lightweight FNV-1a 64-bit style digest of all source files inside [dir].
  static String _computeDirectoryDigest(Directory dir, {Set<String> excludeExt = const {'.crx', '.xpi', '.pem'}}) {
    if (!dir.existsSync()) return '';
    final entries = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final lower = f.path.toLowerCase();
          return !excludeExt.any((ext) => lower.endsWith(ext));
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    var hash = BigInt.parse('14695981039346656037');
    final prime = BigInt.parse('1099511628211');
    final mask = BigInt.parse('18446744073709551615');

    for (final file in entries) {
      final rel = file.path.substring(dir.path.length);
      final nameBytes = utf8.encode(rel);
      List<int> bodyBytes;
      if (rel == '/manifest.json') {
        try {
          final parsed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          parsed.remove('version');
          bodyBytes = utf8.encode(jsonEncode(parsed));
        } catch (_) {
          bodyBytes = file.readAsBytesSync();
        }
      } else {
        bodyBytes = file.readAsBytesSync();
      }
      for (final b in nameBytes) {
        hash = ((hash ^ BigInt.from(b)) * prime) & mask;
      }
      for (final b in bodyBytes) {
        hash = ((hash ^ BigInt.from(b)) * prime) & mask;
      }
    }
    return hash.toRadixString(16);
  }

  static Future<void> _copyExtensionDir(Directory src, Directory dst) async {
    if (dst.existsSync()) {
      await dst.delete(recursive: true);
    }
    await dst.create(recursive: true);
    for (final entity in src.listSync(recursive: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (name.startsWith('.') ||
          name.endsWith('.crx') ||
          name.endsWith('.xpi') ||
          name.endsWith('.pem')) {
        continue;
      }
      if (entity is Directory) {
        await _copyExtensionDir(entity, Directory('${dst.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${dst.path}/$name');
      }
    }
  }

  /// Returns true when a `.xpi` ZIP package contains Mozilla's signature (`META-INF/mozilla.rsa`).
  static bool xpiHasMozillaSignature(File xpiFile) {
    if (!xpiFile.existsSync()) return false;
    try {
      final bytes = xpiFile.readAsBytesSync();
      if (bytes.length < 32 || bytes[0] != 0x50 || bytes[1] != 0x4B) return false;
      final marker = utf8.encode('META-INF/mozilla.rsa');
      for (int i = 0; i <= bytes.length - marker.length; i++) {
        if (bytes[i] != marker[0]) continue;
        var matched = true;
        for (int j = 1; j < marker.length; j++) {
          if (bytes[i + j] != marker[j]) {
            matched = false;
            break;
          }
        }
        if (matched) return true;
      }
    } catch (_) {}
    return false;
  }

  static File? _findPreSignedFirefoxXpi({
    required String chronosDataPath,
    String? rootDir,
  }) {
    final candidates = <String>[
      '$chronosDataPath/chronos-signed.xpi',
      if (rootDir != null && rootDir.isNotEmpty) '$rootDir/chronos_extension_firefox/signed.xpi',
    ];
    for (final p in candidates) {
      final f = File(p);
      if (xpiHasMozillaSignature(f)) return f;
    }
    return null;
  }

  /// Packages signed CRX3, unpacked local Chromium extension, Firefox XPI, CA cert & PAC.
  static Future<PackagingResult> packageAll({
    String? projectRootOverride,
    String? homeDirOverride,
    bool forceRebuild = false,
  }) async {
    final home = homeDirOverride ?? Platform.environment['HOME'] ?? '/tmp';
    final chronosDataDir = Directory('$home/.local/share/chronos');
    await chronosDataDir.create(recursive: true);
    final caPac = await ensureProxyCaAndPac(homeDirOverride: home);

    final root = findProjectRoot(overrideRoot: projectRootOverride);
    final srcChromeDir = root != null
        ? Directory('$root/chronos_extension')
        : Directory('${chronosDataDir.path}/extension');
    if (!srcChromeDir.existsSync() || !File('${srcChromeDir.path}/manifest.json').existsSync()) {
      return PackagingResult(
        success: false,
        version: '0.0.0',
        extensionId: defaultChromeExtensionId,
        caCertPath: caPac.caCertPath,
        pacPath: caPac.pacPath,
        message: 'Fonte chronos_extension não encontrada.',
      );
    }

    // Resolve PEM signing key cleanly.
    String? pemPath;
    final cachedPem = File('${chronosDataDir.path}/chronos_extension.pem');
    final rootPem = root != null ? File('$root/chronos_extension.pem') : null;
    if (rootPem != null && rootPem.existsSync()) {
      pemPath = rootPem.path;
      if (!cachedPem.existsSync()) {
        await rootPem.copy(cachedPem.path);
        await Process.run('chmod', ['0600', cachedPem.path]);
      }
    } else if (cachedPem.existsSync()) {
      pemPath = cachedPem.path;
    } else {
      final genRes = await Process.run('openssl', [
        'genpkey',
        '-algorithm',
        'RSA',
        '-pkeyopt',
        'rsa_keygen_bits:2048',
        '-out',
        cachedPem.path,
      ]);
      if (genRes.exitCode != 0) {
        return PackagingResult(
          success: false,
          version: '0.0.0',
          extensionId: defaultChromeExtensionId,
          caCertPath: caPac.caCertPath,
          pacPath: caPac.pacPath,
          message: 'Falha ao gerar chave RSA da extensão: ${genRes.stderr}',
        );
      }
      await Process.run('chmod', ['0600', cachedPem.path]);
      pemPath = cachedPem.path;
    }

    // Determine monotonic version across builds cleanly.
    final metaFile = File('${chronosDataDir.path}/.ext_build_meta.json');
    Map<String, dynamic> meta = {};
    if (metaFile.existsSync()) {
      try {
        meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }

    final srcManifestRaw = await File('${srcChromeDir.path}/manifest.json').readAsString();
    final srcManifest = jsonDecode(srcManifestRaw) as Map<String, dynamic>;
    final srcVersion = (srcManifest['version'] ?? '1.1.0').toString();
    final lastVersion = (meta['version'] ?? '1.0.0').toString();
    final lastDigest = (meta['chromeDigest'] ?? '').toString();
    final lastFfDigest = (meta['firefoxDigest'] ?? '').toString();
    final curDigest = _computeDirectoryDigest(srcChromeDir);
    final srcFirefoxDir = root != null ? Directory('$root/chronos_extension_firefox') : null;
    final curFfDigest = (srcFirefoxDir != null && srcFirefoxDir.existsSync())
        ? _computeDirectoryDigest(srcFirefoxDir)
        : '';

    String buildVersion = srcVersion;
    if (compareVersions(lastVersion, buildVersion) > 0) {
      buildVersion = lastVersion;
    }
    final contentChanged = (lastDigest.isNotEmpty && lastDigest != curDigest) ||
        (lastFfDigest.isNotEmpty && curFfDigest.isNotEmpty && lastFfDigest != curFfDigest);
    if (contentChanged && compareVersions(buildVersion, lastVersion) <= 0) {
      buildVersion = bumpPatchVersion(buildVersion);
    }

    final guardBuildDir = Directory('${chronosDataDir.path}/guard/build');
    final guardCrxFile = File('${guardBuildDir.path}/chronos.crx');
    final userCrxFile = File('${chronosDataDir.path}/chronos_extension.crx');
    final userUnpackedDir = Directory('${chronosDataDir.path}/extension');

    final needCrxRebuild = forceRebuild ||
        lastDigest != curDigest ||
        (curFfDigest.isNotEmpty && lastFfDigest != curFfDigest) ||
        !guardCrxFile.existsSync() ||
        !userCrxFile.existsSync() ||
        !File('${userUnpackedDir.path}/manifest.json').existsSync() ||
        compareVersions(buildVersion, lastVersion) != 0;

    String resolvedId = defaultChromeExtensionId;
    final stageTempDir = await Directory.systemTemp.createTemp('chronos_pkg_stage_');
    try {
      if (needCrxRebuild) {
        await guardBuildDir.create(recursive: true);
        final chromeStageDir = Directory('${stageTempDir.path}/chrome');
        await _copyExtensionDir(srcChromeDir, chromeStageDir);

        // Write monotonic build version and version-scoped service worker entry
        // so Chromium MV3 never executes an orphaned ScriptCache worker across upgrades.
        final buildManifest = Map<String, dynamic>.from(srcManifest)..['version'] = buildVersion;
        final bgFile = File('${chromeStageDir.path}/background.js');
        if (bgFile.existsSync()) {
          final swName = 'sw_${buildVersion.replaceAll('.', '_')}.js';
          await bgFile.copy('${chromeStageDir.path}/$swName');
          final bgMap = buildManifest['background'];
          if (bgMap is Map) {
            buildManifest['background'] = {
              ...Map<String, dynamic>.from(bgMap),
              'service_worker': swName,
            };
          }
        }
        final manifestStr = const JsonEncoder.withIndent('  ').convert(buildManifest);
        await File('${chromeStageDir.path}/manifest.json').writeAsString('$manifestStr\n', flush: true);

        final tmpZip = File('${stageTempDir.path}/chronos_tmp.zip');
        final zipRes = await Process.run(
          'zip',
          ['-rq', '-X', tmpZip.path, '.'],
          workingDirectory: chromeStageDir.path,
        );
        if (zipRes.exitCode != 0 || !tmpZip.existsSync()) {
          return PackagingResult(
            success: false,
            version: buildVersion,
            extensionId: resolvedId,
            caCertPath: caPac.caCertPath,
            pacPath: caPac.pacPath,
            message: 'Falha ao compactar extensão Chromium: ${zipRes.stderr}',
          );
        }

        final zipBytes = await tmpZip.readAsBytes();
        final crxOut = await buildCrx3Bytes(zipBytes: zipBytes, pemPath: pemPath);
        resolvedId = crxOut.extensionId;

        final tmpGuardCrx = File('${guardCrxFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
        await tmpGuardCrx.writeAsBytes(crxOut.crxBytes, flush: true);
        await tmpGuardCrx.rename(guardCrxFile.path);

        final tmpUserCrx = File('${userCrxFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
        await tmpUserCrx.writeAsBytes(crxOut.crxBytes, flush: true);
        await tmpUserCrx.rename(userCrxFile.path);
        await Process.run('chmod', ['0644', guardCrxFile.path, userCrxFile.path]);

        if (root != null) {
          try {
            final rootCrx = File('$root/chronos_extension.crx');
            final tmpRootCrx = File('${rootCrx.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
            await tmpRootCrx.writeAsBytes(crxOut.crxBytes, flush: true);
            await tmpRootCrx.rename(rootCrx.path);
            await Process.run('chmod', ['0644', rootCrx.path]);
          } catch (_) {}
        }

        // Update unpacked dir atomically-ish via per-call temp dir so parallel tests never race on delete/copy.
        final nextUnpacked = Directory('${chronosDataDir.path}/.extension_next_$pid');
        await _copyExtensionDir(chromeStageDir, nextUnpacked);
        final backupUnpacked = Directory('${chronosDataDir.path}/.extension_old_$pid');
        if (backupUnpacked.existsSync()) {
          try { await backupUnpacked.delete(recursive: true); } catch (_) {}
        }
        if (userUnpackedDir.existsSync()) {
          try { await userUnpackedDir.rename(backupUnpacked.path); } catch (_) {}
        }
        try {
          if (userUnpackedDir.existsSync()) {
            await userUnpackedDir.delete(recursive: true);
          }
          await nextUnpacked.rename(userUnpackedDir.path);
        } catch (_) {
          await _copyExtensionDir(chromeStageDir, userUnpackedDir);
        }
        if (backupUnpacked.existsSync()) {
          try { await backupUnpacked.delete(recursive: true); } catch (_) {}
        }

        final updateXml = '''<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$resolvedId'>
    <updatecheck codebase='file:///usr/local/share/chronos/chronos.crx' version='$buildVersion' />
  </app>
</gupdate>
''';
        await File('${chronosDataDir.path}/guard/update.xml').writeAsString(updateXml, flush: true);
        await File('${guardBuildDir.path}/update.xml').writeAsString(updateXml, flush: true);
      }

      // Preserve a user-supplied Mozilla-signed XPI (`META-INF/mozilla.rsa`) when present;
      // otherwise build a fresh unsigned Firefox XPI in an isolated temp staging directory.
      String? outXpiPath;
      final preSignedXpi = _findPreSignedFirefoxXpi(
        chronosDataPath: chronosDataDir.path,
        rootDir: root,
      );
      if (preSignedXpi != null) {
        final userXpi = File('${chronosDataDir.path}/$firefoxAddonId.xpi');
        final tmpUserXpi = File('${userXpi.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
        await preSignedXpi.copy(tmpUserXpi.path);
        await tmpUserXpi.rename(userXpi.path);
        outXpiPath = userXpi.path;
        try {
          await guardBuildDir.create(recursive: true);
          final tmpGuardXpi = File('${guardBuildDir.path}/chronos.tmp.$pid.xpi');
          await preSignedXpi.copy(tmpGuardXpi.path);
          await tmpGuardXpi.rename('${guardBuildDir.path}/chronos.xpi');
        } catch (_) {}
      } else if (srcFirefoxDir != null &&
          srcFirefoxDir.existsSync() &&
          File('${srcFirefoxDir.path}/manifest.json').existsSync()) {
        final stagingFfDir = Directory('${stageTempDir.path}/firefox');
        await _copyExtensionDir(srcFirefoxDir, stagingFfDir);

        final ffManifestFile = File('${stagingFfDir.path}/manifest.json');
        final ffManifest = jsonDecode(await ffManifestFile.readAsString()) as Map<String, dynamic>;
        ffManifest['version'] = buildVersion;
        await ffManifestFile.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(ffManifest)}\n',
          flush: true,
        );

        final stagedXpi = File('${stageTempDir.path}/addon.xpi');
        final ffZip = await Process.run(
          'zip',
          ['-rq', '-X', stagedXpi.path, '.'],
          workingDirectory: stagingFfDir.path,
        );
        if (ffZip.exitCode == 0 && stagedXpi.existsSync()) {
          final userXpi = File('${chronosDataDir.path}/$firefoxAddonId.xpi');
          final tmpUserXpi = File('${userXpi.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
          await stagedXpi.copy(tmpUserXpi.path);
          await tmpUserXpi.rename(userXpi.path);
          outXpiPath = userXpi.path;

          try {
            await guardBuildDir.create(recursive: true);
            final tmpGuardXpi = File('${guardBuildDir.path}/chronos.tmp.$pid.xpi');
            await stagedXpi.copy(tmpGuardXpi.path);
            await tmpGuardXpi.rename('${guardBuildDir.path}/chronos.xpi');
          } catch (_) {}

          if (root != null) {
            try {
              final tmpRootXpi = File('$root/chronos_extension_firefox.tmp.$pid.xpi');
              await stagedXpi.copy(tmpRootXpi.path);
              await tmpRootXpi.rename('$root/chronos_extension_firefox.xpi');
              final tmpBundledXpi = File('$root/chronos_extension_firefox/$firefoxAddonId.tmp.$pid.xpi');
              await stagedXpi.copy(tmpBundledXpi.path);
              await tmpBundledXpi.rename('$root/chronos_extension_firefox/$firefoxAddonId.xpi');
            } catch (_) {}
          }
        }
      }

      final metaTmp = File('${metaFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
      await metaTmp.writeAsString(
        jsonEncode({
          'version': buildVersion,
          'chromeDigest': curDigest,
          'firefoxDigest': curFfDigest,
          'extensionId': resolvedId,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
      await metaTmp.rename(metaFile.path);

      return PackagingResult(
        success: true,
        version: buildVersion,
        extensionId: resolvedId,
        crxPath: userCrxFile.existsSync() ? userCrxFile.path : null,
        guardCrxPath: guardCrxFile.existsSync() ? guardCrxFile.path : null,
        xpiPath: outXpiPath,
        caCertPath: caPac.caCertPath,
        pacPath: caPac.pacPath,
        message: 'Pacotes CRX3 v$buildVersion ($resolvedId) e XPI prontos.',
      );
    } finally {
      try {
        await stageTempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
