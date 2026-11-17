import 'dart:io';

/// Chronos version baked in at build time by CI:
/// `flutter build linux --dart-define=CHRONOS_VERSION=X.Y.Z`.
/// Local/dev builds report `0.0.0-dev` and never self-update.
const String appVersion = String.fromEnvironment('CHRONOS_VERSION', defaultValue: '0.0.0-dev');

/// GitHub repository that publishes signed releases.
const String updateRepository = 'danielwu05/Chronos';

String get _home => Platform.environment['HOME'] ?? '/tmp';

/// Root of the self-managed install: `~/.local/share/chronos/app`
/// (`versions/X.Y.Z/` + `current -> versions/X.Y.Z`).
String installRootFor([String? homeOverride]) =>
    '${homeOverride ?? _home}/.local/share/chronos/app';

/// True when this process runs from the installed release tree (not from a source checkout).
bool isRunningFromInstallRoot({String? executablePath, String? homeOverride}) {
  final exe = executablePath ?? Platform.resolvedExecutable;
  return exe.startsWith('${installRootFor(homeOverride)}/');
}

/// Release builds installed by `install.sh` / the updater are the only ones that self-update.
bool get isReleaseBuild => !appVersion.endsWith('-dev') && isRunningFromInstallRoot();
