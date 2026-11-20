import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';

import '../main.dart' show chronosDbPath;
import '../services/app_lifecycle_service.dart';
import '../src/rust/api/simple.dart';

/// The only way to quit Chronos: uninstall it (extensions, guard, daemon, autostart),
/// optionally deleting all data. Refused while anti-cheat is active.
Future<void> showUninstallDialog(BuildContext context) async {
  bool acActive = false;
  try {
    acActive = (await getAntiCheatState()).isActive;
  } catch (_) {}
  if (!context.mounted) return;

  if (acActive) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.naoEPossivelDesinstalar),
        content: Text(
          tr.oAntiBurlaEstaAtivoEnquanto,
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.entendi))],
      ),
    );
    return;
  }

  bool deleteData = false;
  bool running = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr.desinstalarOChronos),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.istoRemoveOChronosDoComputador,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteData,
                onChanged: running ? null : (v) => setState(() => deleteData = v ?? false),
                title: Text(tr.apagarTambemMeusDados),
                subtitle: Text(tr.regrasHistoricoDeUsoEConfiguracoes),
              ),
              if (running) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: running ? null : () => Navigator.pop(ctx), child: Text(tr.cancelar)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: running
                ? null
                : () async {
                    setState(() {
                      running = true;
                      error = null;
                    });
                    final err = await AppLifecycleService.instance.uninstall(
                      deleteData: deleteData,
                      dbPath: chronosDbPath,
                    );
                    // On success the process exits; only errors return here.
                    setState(() {
                      running = false;
                      error = err;
                    });
                  },
            child: Text(tr.desinstalar),
          ),
        ],
      ),
    ),
  );
}
