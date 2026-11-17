import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:flutter/material.dart';

/// Displays the 3-stage offline browser protection pipeline:
/// 1. Bundled/generated package -> 2. Chronos Guard policy -> 3. Active in browsers.
class BrowserSetupFlowStepper extends StatelessWidget {
  final bool hasPackages;
  final ChronosGuardStatus? guardStatus;
  final List<DetectedBrowser> browsers;

  const BrowserSetupFlowStepper({
    super.key,
    required this.hasPackages,
    required this.guardStatus,
    required this.browsers,
  });

  @override
  Widget build(BuildContext context) {
    final guardActive = guardStatus?.isFullyActive == true;
    final guardOutdated = guardStatus?.isGuardOutdated == true;
    final allBrowsersReady = browsers.isNotEmpty &&
        browsers.every((b) => BrowserExtensionInstaller.describeBrowserStatus(b).installed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildStepChip(
            step: '1',
            label: 'Pacote Embutido',
            done: hasPackages,
            warning: false,
          ),
          const Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
          _buildStepChip(
            step: '2',
            label: guardOutdated ? 'Atualizar Guard' : 'Política Guard',
            done: guardActive,
            warning: guardOutdated || (guardStatus?.isInstalled == false),
          ),
          const Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
          _buildStepChip(
            step: '3',
            label: 'Ativo nos Navegadores',
            done: allBrowsersReady,
            warning: browsers.isNotEmpty && !allBrowsersReady,
          ),
        ],
      ),
    );
  }

  Widget _buildStepChip({
    required String step,
    required String label,
    required bool done,
    required bool warning,
  }) {
    final color = done
        ? Colors.tealAccent
        : (warning ? Colors.orangeAccent : Colors.white60);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          '$step. $label',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: done ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Shared status chip wrap displaying truthful per-browser status.
class BrowserStatusChipsWrap extends StatelessWidget {
  final List<DetectedBrowser> browsers;
  final void Function(String message, bool ok)? onFeedback;
  final VoidCallback? onShowChromeGuide;
  final VoidCallback? onShowFirefoxGuide;
  final Future<void> Function(DetectedBrowser browser)? onRequestRelaunch;

  const BrowserStatusChipsWrap({
    super.key,
    required this.browsers,
    this.onFeedback,
    this.onShowChromeGuide,
    this.onShowFirefoxGuide,
    this.onRequestRelaunch,
  });

  @override
  Widget build(BuildContext context) {
    if (browsers.isEmpty) {
      return const Text(
        'Nenhum navegador suportado detectado.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: browsers.map((b) {
        final st = BrowserExtensionInstaller.describeBrowserStatus(b);
        final isChrome =
            b.executable.contains('google-chrome') || b.id.contains('google-chrome');
        final isFirefox = b.family == 'firefox';

        final chip = ActionChip(
          avatar: Icon(
            st.installed
                ? Icons.check_circle
                : (st.pendingMessage != null
                    ? Icons.restart_alt
                    : ((isChrome || isFirefox)
                        ? Icons.help_outline
                        : Icons.warning_amber_rounded)),
            size: 16,
            color: st.installed ? Colors.tealAccent : Colors.orangeAccent,
          ),
          label: Text(
            '${b.name} (${st.statusLabel})',
            style: TextStyle(
              fontSize: 12,
              color: st.installed ? Colors.white : Colors.orangeAccent,
            ),
          ),
          backgroundColor: st.installed
              ? Colors.teal.shade900.withValues(alpha: 0.3)
              : Colors.orange.shade900.withValues(alpha: 0.2),
          onPressed: st.installed
              ? null
              : () async {
                  if (st.pendingMessage != null) {
                    if (b.family == 'chromium' &&
                        BrowserExtensionInstaller.isBrowserProcessRunning(b) &&
                        onRequestRelaunch != null) {
                      await onRequestRelaunch!(b);
                      return;
                    }
                    onFeedback?.call(st.pendingMessage!, false);
                  } else if (isChrome) {
                    onShowChromeGuide?.call();
                  } else if (isFirefox) {
                    onShowFirefoxGuide?.call();
                  }
                },
        );
        final tooltipMsg = st.pendingMessage ??
            (isFirefox && st.installed
                ? 'Protegido pelo Proxy Seletivo Local (127.0.0.1:4546) + Certificado CA — o Firefox Release não lista .xpi sem assinatura Mozilla em about:addons, mas bloqueios e filtros HTML/CSS operam normalmente.'
                : null);
        return tooltipMsg != null ? Tooltip(message: tooltipMsg, child: chip) : chip;
      }).toList(),
    );
  }
}

/// Collapsed advanced/manual fallback controls kept out of the primary 1-click flow.
class ManualBrowserFallbackTile extends StatelessWidget {
  final List<DetectedBrowser> browsers;
  final void Function(String message, bool ok) onFeedback;
  final VoidCallback? onShowChromeGuide;
  final VoidCallback? onShowFirefoxGuide;
  final VoidCallback? onShowGuardTerminal;

  const ManualBrowserFallbackTile({
    super.key,
    required this.browsers,
    required this.onFeedback,
    this.onShowChromeGuide,
    this.onShowFirefoxGuide,
    this.onShowGuardTerminal,
  });

  @override
  Widget build(BuildContext context) {
    final hasChrome = browsers.any(
      (b) => b.executable.contains('google-chrome') || b.id.contains('google-chrome'),
    );
    final hasFirefox = browsers.any((b) => b.family == 'firefox');

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 6, bottom: 4),
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white54,
        title: const Text(
          'Instalação Manual / Fallback Avançado',
          style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.download, size: 15),
                  label: const Text('Baixar Chrome (.zip)', style: TextStyle(fontSize: 12)),
                  onPressed: () async {
                    final zip = await BrowserExtensionInstaller.exportExtensionZipToDownloads();
                    onFeedback(
                      zip != null ? 'Extensão salva em: $zip' : 'Erro ao salvar zip em Downloads.',
                      zip != null,
                    );
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.download, size: 15),
                  label: const Text('Baixar Firefox (.xpi)', style: TextStyle(fontSize: 12)),
                  onPressed: () async {
                    final xpi =
                        await BrowserExtensionInstaller.exportFirefoxExtensionZipToDownloads();
                    onFeedback(
                      xpi != null ? 'Extensão salva em: $xpi' : 'Erro ao salvar xpi em Downloads.',
                      xpi != null,
                    );
                  },
                ),
                if (hasChrome && onShowChromeGuide != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 15),
                    label: const Text('Ativar no Chrome (Manual)', style: TextStyle(fontSize: 12)),
                    onPressed: onShowChromeGuide,
                  ),
                if (hasFirefox && onShowFirefoxGuide != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 15),
                    label: const Text('Ativar no Firefox (Manual)', style: TextStyle(fontSize: 12)),
                    onPressed: onShowFirefoxGuide,
                  ),
                if (onShowGuardTerminal != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    icon: const Icon(Icons.terminal, size: 15),
                    label: const Text('Comando Terminal (Guard)', style: TextStyle(fontSize: 12)),
                    onPressed: onShowGuardTerminal,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks explicit confirmation from the user before closing and relaunching
/// open Chromium-family browsers so no active tabs are killed silently.
Future<void> showConfirmRelaunchBrowsersDialog(
  BuildContext context,
  List<DetectedBrowser> pendingBrowsers, {
  Future<void> Function()? onCompleted,
  void Function(String message, bool ok)? onFeedback,
}) async {
  if (pendingBrowsers.isEmpty || !context.mounted) return;
  final names = pendingBrowsers.map((b) => '• ${b.name}').join('\n');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF161922),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.restart_alt, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reiniciar Navegadores para Ativar?',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(
          'Os seguintes navegadores já estão abertos e precisam ser fechados e reabertos para carregar a extensão Chronos:\n\n'
          '$names\n\n'
          'Deseja fechar e reabrir esses navegadores agora?',
          style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.45),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Agora Não'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Fechar e Reabrir Agora'),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    for (final browser in pendingBrowsers) {
      await BrowserExtensionInstaller.relaunchBrowser(browser);
    }
    await Future.delayed(const Duration(milliseconds: 900));
    await onCompleted?.call();
    onFeedback?.call(
      'Navegadores reiniciados (${pendingBrowsers.map((b) => b.name).join(', ')})!',
      true,
    );
  }
}

/// Runs the full 1-click setup workflow and coordinates optional confirmed restart.
Future<UnifiedBrowserSetupResult> runUnifiedBrowserSetupFlow(
  BuildContext context, {
  required bool isAntiCheatActive,
  required Future<void> Function() onRefresh,
  required void Function(String message, bool ok) onFeedback,
  VoidCallback? onPolkitFallback,
}) async {
  final result = await ChronosGuardService.installAndProtectAllBrowsers(
    isAntiCheatActive: isAntiCheatActive,
  );
  await onRefresh();
  onFeedback(result.message, result.success);

  if (result.polkitUnavailableOrCancelled && onPolkitFallback != null && context.mounted) {
    onPolkitFallback();
  }

  if (result.openPendingChromiumBrowsers.isNotEmpty && context.mounted) {
    await showConfirmRelaunchBrowsersDialog(
      context,
      result.openPendingChromiumBrowsers,
      onCompleted: onRefresh,
      onFeedback: onFeedback,
    );
  }
  return result;
}
