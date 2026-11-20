// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import '../services/app_locale.dart';
import '../src/rust/api/adult.dart';

/// Full-screen cover shown when the daemon's whole-screen detector finds +18 content
/// in any app, or when a blocked app was opened and closed by the engine
/// (see rust/src/screen_guard.rs). The app window is brought to the front,
/// made full screen and kept on top; "go back" unlocks after a few seconds and restores
/// the window as it was (hidden in the tray or normal).
class ScreenBlockGuard extends StatefulWidget {
  final Widget child;

  const ScreenBlockGuard({super.key, required this.child});

  @override
  State<ScreenBlockGuard> createState() => _ScreenBlockGuardState();
}

class _ScreenBlockGuardState extends State<ScreenBlockGuard> {

  Timer? _poll;
  Timer? _countdown;
  int _lastSeq = -1;
  ScreenAlertDto? _alert;
  bool _wasVisible = true;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _lastSeq = _read()?.seq.toInt() ?? 0; // never react to an old alert
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  ScreenAlertDto? _read() {
    try {
      return getScreenAlert();
    } catch (_) {
      return null;
    }
  }

  Future<void> _check() async {
    final alert = _read();
    if (alert == null || alert.seq.toInt() <= _lastSeq) return;
    _lastSeq = alert.seq.toInt();
    final age = DateTime.now().millisecondsSinceEpoch - alert.atMs.toInt();
    if (age > 15000) return;
    final alreadyShown = _alert != null;
    setState(() {
      _alert = alert;
      // +18: 5 s before going back; blocked app: 3 s.
      _secondsLeft = alert.kind == 'app' ? 3 : 5;
    });
    _startCountdown();
    if (!alreadyShown) {
      try {
        _wasVisible = await windowManager.isVisible();
      } catch (_) {}
    }
    await _coverScreen();
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 99));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _coverScreen() async {
    try {
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setFullScreen(true);
      await windowManager.focus();
      // Hyprland: jump to the app's workspace so the offending window is out of view.
      await Process.run('hyprctl', ['dispatch', 'focuswindow', 'pid:$pid']);
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    _countdown?.cancel();
    setState(() => _alert = null);
    try {
      await windowManager.setFullScreen(false);
      await windowManager.setAlwaysOnTop(false);
      if (!_wasVisible) await windowManager.hide();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final alert = _alert;
    final isApp = alert?.kind == 'app';
    final name = (alert == null || alert.name.isEmpty) ? '?' : alert.name;
    final title = isApp ? tr.appBloqueadoTitulo(name) : tr.conteudoAdultoDetectadoNaTela;
    final body = isApp ? '${_reasonText(alert!.reason)} ${tr.appFechadoPeloChronos}' : tr.coberturaTelaTexto(name);
    return Stack(
      children: [
        widget.child,
        if (alert != null)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF0B0D12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isApp ? Icons.block_rounded : Icons.visibility_off_rounded,
                            size: 72, color: Colors.redAccent),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            _secondsLeft > 0 ? '${tr.entendiVoltar} ($_secondsLeft)' : tr.entendiVoltar,
                          ),
                          onPressed: _secondsLeft > 0 ? null : _dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _reasonText(String reason) => switch (reason) {
        'window' => tr.motivoJanela,
        'forced' => tr.motivoForcado,
        'penalty' => tr.motivoPenalidade,
        'leisure' => tr.motivoLazer,
        _ => tr.motivoQuota,
      };
}
