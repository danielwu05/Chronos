import 'package:chronos_app/services/app_locale.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../src/rust/api/simple.dart';
import '../services/browser_extension_installer.dart';
import '../services/app_profile.dart';
import '../services/web_block_server.dart';

/// Notifies active UI listeners (e.g. GeneralSettingsView inside IndexedStack)
/// whenever Anti-Burla activation/deactivation changes anywhere in the app.
final ValueNotifier<int> antiCheatStateRevision = ValueNotifier<int>(0);

void notifyAntiCheatStateChanged() {
  antiCheatStateRevision.value++;
  WebBlockServer.nudgeObservers();
}

class AntiCheatDialog extends StatefulWidget {
  final VoidCallback onStateChanged;

  const AntiCheatDialog({super.key, required this.onStateChanged});

  /// Opens the Anti-Burla dialog and resolves `true` once Anti-Burla is inactive (`OFF`).
  static Future<bool> showUnlockChallenge(
    BuildContext context, {
    required VoidCallback onStateChanged,
  }) async {
    final current = await getAntiCheatState();
    if (!current.isActive) return true;
    if (!context.mounted) return false;
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AntiCheatDialog(onStateChanged: onStateChanged),
    );
    if (unlocked == true) return true;
    final after = await getAntiCheatState();
    return !after.isActive;
  }

  @override
  State<AntiCheatDialog> createState() => _AntiCheatDialogState();
}

class _AntiCheatDialogState extends State<AntiCheatDialog> {
  AntiCheatStateDto? _state;
  bool _loading = true;
  String _selectedMode = 'CHALLENGE'; // 'CHALLENGE' ou 'NUKE'
  int _nukeDays = 1; // Default 1 dia (01:00:00)
  int _nukeHours = 0;
  int _nukeMinutes = 0;
  Timer? _countdownTimer;

  // Variáveis para o Desafio de Digitação StayFocusd
  final TextEditingController _challengeController = TextEditingController();
  String _challengeError = '';
  int _challengeProgress = 0;
  int _challengeResets = 0;
  final FocusNode _challengeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != null && _state!.mode == 'NUKE' && _state!.nukeRemainingSeconds > 0) {
        setState(() {
          final newSecs = _state!.nukeRemainingSeconds - 1;
          _state = AntiCheatStateDto(
            isActive: newSecs > 0,
            mode: newSecs > 0 ? 'NUKE' : 'OFF',
            nukeRemainingSeconds: newSecs > 0 ? newSecs : 0,
            challengeText: _state!.challengeText,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    // Every time the challenge is closed, the next one uses another text from the pool.
    if (_state?.isActive == true && _state?.mode == 'CHALLENGE') {
      redrawChallengeText().catchError((_) => const ActionFeedback(success: false, message: ''));
    }
    _countdownTimer?.cancel();
    _challengeController.dispose();
    _challengeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    try {
      final s = await getAntiCheatState();
      setState(() {
        _state = s;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  bool _isComposingDeadKey(String text, String expected) {
    if (text.isEmpty) return false;
    final lastChar = text[text.length - 1];
    const deadKeys = {'´', '`', '^', '~', '¨', '\u02DC', '\u02C6'};
    final isCombining = lastChar.codeUnits.any((c) => c >= 0x0300 && c <= 0x036F);
    if (deadKeys.contains(lastChar) || isCombining) {
      final prefix = text.substring(0, text.length - 1);
      if (expected.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  void _onChallengeTextChanged(String text) {
    if (_state == null) return;
    final expected = _state!.challengeText;

    if (text.isEmpty) {
      setState(() {
        _challengeError = '';
        _challengeProgress = 0;
      });
      return;
    }

    // Any other paste (middle-click / primary selection, drag and drop) shows up as
    // several characters at once: treat it like a typo and reset.
    if (text.length - _challengeProgress > 3) {
      _challengeController.clear();
      _challengeResets++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _challengeFocus.requestFocus();
      });
      setState(() {
        _challengeError = tr.colarNaoEPermitidoDigiteO;
        _challengeProgress = 0;
      });
      return;
    }

    // Se estiver no meio da composição de um acento (dead key em teclados ABNT2/US-Intl),
    // não acusa erro nem reseta prematuramente.
    if (_isComposingDeadKey(text, expected)) {
      return;
    }

    // Validação estrita caractere por caractere
    if (!expected.startsWith(text)) {
      // Errou! Reseta imediatamente como no StayFocusd
      HapticFeedback.heavyImpact();
      _challengeController.clear();
      _challengeResets++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _challengeFocus.requestFocus();
      });
      setState(() {
        _challengeError = tr.erroDetectadoNoModoStayfocusdQualquer;
        _challengeProgress = 0;
      });
      return;
    }

    setState(() {
      _challengeError = '';
      _challengeProgress = text.length;
    });
  }

  Future<void> _enableAntiCheat() async {
    try {
      final totalNukeSeconds = _selectedMode == 'NUKE'
          ? ((_nukeDays * 86400) + (_nukeHours * 3600) + (_nukeMinutes * 60))
          : null;

      if (_selectedMode == 'NUKE' && (totalNukeSeconds == null || totalNukeSeconds <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr.selecioneUmaDuracaoValidaMaiorQue),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // Risk warning: while active, Chronos cannot be closed or uninstalled.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr.ativarOAntiBurla),
          content: Text(
            tr.enquantoOAntiBurlaEstiverAtivo(_selectedMode == 'NUKE' ? tr.noModoNukeIssoSoAcaba : tr.paraDesativarSeraPrecisoCompletarO),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancelar)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr.entendiAtivar),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await enableAntiCheat(mode: _selectedMode, nukeSeconds: totalNukeSeconds);

      // Protege extensões nos navegadores detectados
      await BrowserExtensionInstaller.installAll(isAntiCheatActive: true);

      notifyAntiCheatStateChanged();
      widget.onStateChanged();

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final durationLabel = '${_nukeDays.toString().padLeft(2, '0')}d ${_nukeHours.toString().padLeft(2, '0')}h ${_nukeMinutes.toString().padLeft(2, '0')}m';
        // Back to the main app (do not show the unlock challenge right after activating).
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(_selectedMode == 'NUKE'
                ? tr.modoNukeAtivadoPorP0Configuracoes(durationLabel)
                : tr.modoAntiCheatAtivadoComDesafio),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.erroAoAtivarP0(e)), backgroundColor: Colors.red[800]),
        );
      }
    }
  }

  Future<void> _disableWithChallenge() async {
    try {
      final text = _challengeController.text;
      await disableAntiCheat(verificationToken: text);
      notifyAntiCheatStateChanged();
      widget.onStateChanged();
      await _loadState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr.antiCheatDesativadoComSucessoModificacoes),
            backgroundColor: Colors.blueAccent,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _challengeError = tr.erroP0(e);
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (days > 0) {
      return '${days}d ${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: const Color(0xFF1E222D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final isActive = _state?.isActive ?? false;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isActive
                    ? (_state?.mode == 'NUKE' ? Icons.warning_amber_rounded : Icons.security_rounded)
                    : Icons.shield_outlined,
                color: isActive ? (_state?.mode == 'NUKE' ? Colors.deepOrange : Colors.amber) : Colors.cyanAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isActive ? tr.protecaoAntiCheatAtiva : tr.configurarModoAntiCheat,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),

          if (!isActive) ...[
            Text(
              tr.oAntiCheatImpedeVoceDe,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(tr.escolhaOMetodoDeTravamento, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),

            // Opção 1: StayFocusd Challenge
            _buildModeCard(
              modeKey: 'CHALLENGE',
              title: tr.desafioDeDigitacaoEstritoEstiloStayfocusd,
              desc: tr.qualquerTentativaDeDesativarOuAumentar,
              icon: Icons.keyboard_rounded,
              color: Colors.amber,
            ),
            const SizedBox(height: 10),

            // Opção 2: Modo Nuke (Nuclear Option)
            _buildModeCard(
              modeKey: 'NUKE',
              title: tr.modoNukeBloqueioTotalPorTempo,
              desc: tr.trava100OChronosPorUm,
              icon: Icons.timer_rounded,
              color: Colors.deepOrangeAccent,
            ),

            if (_selectedMode == 'NUKE') ...[
              const SizedBox(height: 16),
              Text(
                tr.duracaoDoTravamentoNukeScrollPara,
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161922),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrangeAccent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('DIAS', style: TextStyle(color: Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('HORAS', style: TextStyle(color: Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('MINUTOS', style: TextStyle(color: Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: CupertinoTheme(
                        data: const CupertinoThemeData(
                          brightness: Brightness.dark,
                          textTheme: CupertinoTextThemeData(
                            pickerTextStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Tambor de Dias (0 a 30 dias, default 1)
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: FixedExtentScrollController(initialItem: _nukeDays),
                                itemExtent: 36,
                                onSelectedItemChanged: (d) => setState(() => _nukeDays = d),
                                children: List.generate(31, (i) => Center(child: Text('${i.toString().padLeft(2, '0')} d'))),
                              ),
                            ),
                            const Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrangeAccent)),
                            // Tambor de Horas (0 a 23 horas, default 0)
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: FixedExtentScrollController(initialItem: _nukeHours),
                                itemExtent: 36,
                                onSelectedItemChanged: (h) => setState(() => _nukeHours = h),
                                children: List.generate(24, (i) => Center(child: Text('${i.toString().padLeft(2, '0')} h'))),
                              ),
                            ),
                            const Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrangeAccent)),
                            // Tambor de Minutos (0 a 59 min, default 0)
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: FixedExtentScrollController(initialItem: _nukeMinutes),
                                itemExtent: 36,
                                onSelectedItemChanged: (m) => setState(() => _nukeMinutes = m),
                                children: List.generate(60, (i) => Center(child: Text('${i.toString().padLeft(2, '0')} m'))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer, color: Colors.deepOrangeAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_nukeDays.toString().padLeft(2, '0')}d : ${_nukeHours.toString().padLeft(2, '0')}h : ${_nukeMinutes.toString().padLeft(2, '0')}m',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: Colors.deepOrangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedMode == 'NUKE' ? Colors.deepOrange : Colors.amber[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.lock_clock),
              label: Text(
                _selectedMode == 'NUKE'
                    ? tr.ativarModoNukeP0('${_nukeDays.toString().padLeft(2, '0')}d ${_nukeHours.toString().padLeft(2, '0')}h ${_nukeMinutes.toString().padLeft(2, '0')}m')
                    : tr.ativarAntiCheatRestrito,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _enableAntiCheat,
            ),
          ] else ...[
            // Anti-Burla está ATIVO
            if (_state?.mode == 'NUKE') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.lock, color: Colors.deepOrangeAccent, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      tr.modoNukeEmAndamento,
                      style: TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatDuration(_state!.nukeRemainingSeconds),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr.nenhumaAlteracaoDeTempoDeTela,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Modo Desafio StayFocusd Ativo
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text(
                          tr.desafioDeDigitacaoStayfocusd,
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr.paraDestravarOAplicativoELiberar,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141721),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _state!.challengeText,
                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4, fontStyle: FontStyle.italic),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Barra de Progresso
                    LinearProgressIndicator(
                      value: _state!.challengeText.isNotEmpty
                          ? (_challengeProgress / _state!.challengeText.length).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr.progressoP0P1Caracteres(_challengeProgress, _state!.challengeText.length),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),

                    if (_challengeError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _challengeError,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],

                    const SizedBox(height: 12),
                    // Undo/redo would bring back the text wiped by a typo: disabled, and the
                    // field is recreated on each reset so no undo history survives.
                    Actions(
                      actions: <Type, Action<Intent>>{
                        UndoTextIntent: DoNothingAction(consumesKey: true),
                        RedoTextIntent: DoNothingAction(consumesKey: true),
                        // No pasting: Ctrl+V / Shift+Insert.
                        PasteTextIntent: DoNothingAction(consumesKey: true),
                      },
                      child: TextField(
                      key: ValueKey('challenge_$_challengeResets'),
                      // No right-click menu (it offered "Paste").
                      contextMenuBuilder: null,
                      focusNode: _challengeFocus,
                      controller: _challengeController,
                      onChanged: _onChallengeTextChanged,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: tr.comeceADigitarOTextoAqui,
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF141721),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.cyanAccent),
                        ),
                      ),
                    ),
                    ),
                    const SizedBox(height: 12),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _challengeProgress == _state!.challengeText.length
                            ? Colors.green[700]
                            : Colors.white24,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _challengeProgress == _state!.challengeText.length
                          ? _disableWithChallenge
                          : null,
                      child: Text(tr.destravarAntiCheat),
                    ),
                  ],
                ),
              ),
            ],
            if (ChronosProfile.isDev) const SizedBox(height: 16),
            if (ChronosProfile.isDev) ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.bug_report, size: 20),
              label: Text(tr.debugDesativarAntiCheatImediatamente),
              onPressed: () async {
                await debugDisableAntiCheat();
                notifyAntiCheatStateChanged();
                widget.onStateChanged();
                await _loadState();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr.debugAntiCheatENukeDesativados),
                      backgroundColor: Colors.purple,
                    ),
                  );
                  Navigator.of(context).pop(true);
                }
              },
            ),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.cyanAccent,
              side: const BorderSide(color: Colors.cyanAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.extension_rounded),
            label: Text(tr.instalarAtualizarExtensaoEmTodosNavegadores),
            onPressed: () async {
              final res = await BrowserExtensionInstaller.installAll(
                isAntiCheatActive: _state?.isActive ?? false,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor: res.success ? Colors.green[800] : Colors.red[800],
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required String modeKey,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMode == modeKey;

    return InkWell(
      onTap: () => setState(() => _selectedMode = modeKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF262B3A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isSelected ? color : Colors.white60, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? color : Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}
