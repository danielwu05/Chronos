import 'dart:io';

import 'package:flutter/foundation.dart';

/// Release vs dev profile (mirrors `rust/src/profile.rs`).
///
/// Debug builds (`flutter run`, `flutter build linux --debug`, `scripts/dev.sh`) are the
/// **dev** profile and run side by side with the installed release:
/// separate ports (5545/5546), data dir (`~/.local/share/chronos-dev`), database
/// (`chronos-dev.db`) and daemon service; no autostart, closing quits, no debug-free
/// restrictions, and it never touches system integrations (browser policies/extensions,
/// guard, DNS, launcher wrappers).
class ChronosProfile {
  /// Debug builds are dev; unit tests (`FLUTTER_TEST`) behave like release.
  static final bool isDev = kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST');

  static int get apiPort => isDev ? 5545 : 4545;
  static int get proxyPort => isDev ? 5546 : 4546;
  static String get apiBase => 'http://127.0.0.1:$apiPort';
  static String get dataDirName => isDev ? 'chronos-dev' : 'chronos';
  static String get dbFileName => isDev ? 'chronos-dev.db' : 'chronos.db';
  static String get daemonServiceName => isDev ? 'chronos-proxy-dev.service' : 'chronos-proxy.service';

  static String get _home => Platform.environment['HOME'] ?? '/tmp';
  static String get dataDir => '$_home/.local/share/$dataDirName';

  /// Release data dir: the CA/PAC are shared so the dev daemon can intercept with the
  /// certificate browsers already trust.
  static String get releaseDataDir => '$_home/.local/share/chronos';

  static const String devUnavailableMessage =
      'Indisponível no modo dev: o ambiente de desenvolvimento não altera navegadores nem o sistema.';
}
