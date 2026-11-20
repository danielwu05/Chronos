// ignore_for_file: deprecated_member_use
import 'package:chronos_app/services/app_locale.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../src/rust/api/simple.dart';
import 'app_profile.dart';
import 'browser_extension_installer.dart';
import 'chronos_daemon_service.dart';
import 'chronos_guard_service.dart';

/// Keeps Chronos running in the background:
/// - closing the window only hides it (single instance: reopening from the menu or tray
///   brings it back);
/// - it starts at login (`--background`) and the `chronos_proxy` daemon relaunches it if
///   the process is killed (see `app.json`);
/// - the only way out is [uninstall], which is refused while anti-cheat is active.
class AppLifecycleService with WindowListener, TrayListener {
  AppLifecycleService._();
  static final AppLifecycleService instance = AppLifecycleService._();

  /// Set when the user picks "Desinstalar…" from the tray; the UI listens and opens the dialog.
  final ValueNotifier<int> uninstallRequests = ValueNotifier(0);

  static String get _home => Platform.environment['HOME'] ?? '/tmp';
  static String get chronosDataDir => ChronosProfile.dataDir;
  static String get appStateFile => '$chronosDataDir/app.json';
  static String get uninstallingMarker => '$chronosDataDir/.uninstalling';
  static String get autostartFile => '$_home/.config/autostart/chronos.desktop';

  static bool isBackgroundLaunch(List<String> args) => args.contains('--background');

  Future<void> start() async {
    if (!Platform.isLinux) return;
    if (ChronosProfile.isDev) {
      // Dev builds close normally, never autostart and are never relaunched.
      _removeDevLeftovers();
      return;
    }
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await _registerProcess();
    await _writeAutostart();
    await _writeDesktopEntry();
    unawaited(_initTray());
    _watchTrayHost();
  }

  static String get desktopEntryFile => '$_home/.local/share/applications/chronos.desktop';

  /// Menu entry: launching it activates the single running instance, which shows the
  /// window (the only way back when no tray is available).
  Future<void> _writeDesktopEntry() async {
    try {
      final f = File(desktopEntryFile);
      final content = '''[Desktop Entry]
Type=Application
Name=Chronos
Comment=Foco e tempo de tela
Exec="${Platform.resolvedExecutable}"
Icon=preferences-system-time
Terminal=false
Categories=Utility;
''';
      if (f.existsSync() && f.readAsStringSync() == content) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(content, flush: true);
    } catch (_) {}
  }

  Timer? _trayWatch;
  String? _trayHostOwner;

  /// At login Chronos may start before the panel's tray (StatusNotifierWatcher); the
  /// icon is only registered when the watcher exists. Re-register whenever the watcher
  /// appears or restarts (e.g. waybar reload).
  void _watchTrayHost() {
    _trayHostOwner = null;
    _trayWatch?.cancel();
    _trayWatch = Timer.periodic(const Duration(seconds: 3), (_) async {
      final owner = await _statusNotifierWatcherOwner();
      if (owner == null || owner == _trayHostOwner) return;
      final first = _trayHostOwner == null;
      _trayHostOwner = owner;
      // The first sighting right after startup is the watcher _initTray already used.
      if (first && _trayHadHost) return;
      try {
        await trayManager.destroy();
      } catch (_) {}
      await _initTray();
    });
  }

  bool _trayHadHost = false;
  bool _trayListening = false;

  static Future<String?> _statusNotifierWatcherOwner() async {
    try {
      final r = await Process.run('busctl', ['--user', 'status', 'org.kde.StatusNotifierWatcher']);
      if (r.exitCode != 0) return null;
      final m = RegExp(r'^PID=(\d+)', multiLine: true).firstMatch(r.stdout.toString());
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Earlier dev builds registered autostart/relaunch pointing at the source checkout
  /// (`.../build/linux/...`): remove those so only the installed release autostarts.
  void _removeDevLeftovers() {
    final releaseDir = ChronosProfile.releaseDataDir;
    for (final path in [autostartFile, '$releaseDir/app.json']) {
      try {
        final f = File(path);
        if (f.existsSync() && f.readAsStringSync().contains('/build/linux/')) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Records pid + executable so the daemon can relaunch Chronos if it gets killed.
  Future<void> _registerProcess() async {
    try {
      await Directory(chronosDataDir).create(recursive: true);
      final marker = File(uninstallingMarker);
      if (marker.existsSync()) marker.deleteSync();
      final tmp = File('$appStateFile.tmp');
      await tmp.writeAsString(jsonEncode({'pid': pid, 'exe': Platform.resolvedExecutable}), flush: true);
      tmp.renameSync(appStateFile);
    } catch (_) {}
  }

  Future<void> _writeAutostart() async {
    try {
      final f = File(autostartFile);
      final content = '''[Desktop Entry]
Type=Application
Name=Chronos
Comment=Chronos em segundo plano
Exec="${Platform.resolvedExecutable}" --background
Icon=preferences-system-time
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=true
''';
      if (f.existsSync() && f.readAsStringSync() == content) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(content, flush: true);
    } catch (_) {}
  }

  Future<void> _initTray() async {
    _trayHadHost = await _statusNotifierWatcherOwner() != null;
    try {
      if (!_trayListening) {
        trayManager.addListener(this);
        _trayListening = true;
      }
      await trayManager.setIcon('assets/tray_icon.png');
      await trayManager.setToolTip(tr.chronos);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'open', label: tr.abrirChronos),
        MenuItem.separator(),
        MenuItem(key: 'uninstall', label: tr.desinstalarChronos),
      ]));
    } catch (e) {
      debugPrint('Chronos tray indisponível: $e');
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    // Closing never quits Chronos: it keeps tracking time in the background.
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showWindow();
      case 'uninstall':
        showWindow();
        uninstallRequests.value++;
    }
  }

  /// Fully removes Chronos (extensions, guard, daemon, autostart, installed app files)
  /// and, when [deleteData] is true, the database and all local data. Refused while
  /// anti-cheat is active. Returns an error message, or exits the process on success.
  Future<String?> uninstall({required bool deleteData, required String dbPath}) async {
    try {
      final ac = await getAntiCheatState();
      if (ac.isActive) {
        return tr.antiBurlaAtivoOChronosNao;
      }
    } catch (_) {}

    // Stop the daemon from relaunching us while we tear everything down.
    try {
      await Directory(chronosDataDir).create(recursive: true);
      File(uninstallingMarker).writeAsStringSync(DateTime.now().toIso8601String());
    } catch (_) {}

    // Extensions + root guard (asks for the admin password when the guard is installed).
    final res = await ChronosGuardService.verifyAntiCheatAndUninstall();
    if (!res.success) {
      try {
        File(uninstallingMarker).deleteSync();
      } catch (_) {}
      return res.message;
    }
    await BrowserExtensionInstaller.removeExtensionFromUserBrowsers();

    // Daemon service.
    final unit = ChronosDaemonService.serviceName;
    await Process.run('systemctl', ['--user', 'disable', '--now', unit]);
    for (final p in [
      '$_home/.config/systemd/user/$unit',
      autostartFile,
      appStateFile,
      '$_home/.local/share/applications/chronos.desktop',
    ]) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await Process.run('systemctl', ['--user', 'daemon-reload']);

    // Installed release files (never the source checkout).
    for (final d in ['$chronosDataDir/app', '$chronosDataDir/bin']) {
      try {
        final dir = Directory(d);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }

    if (deleteData) {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        try {
          final f = File('$dbPath$suffix');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      try {
        final dir = Directory(chronosDataDir);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }

    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    exit(0);
  }
}
