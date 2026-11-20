import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

class FocusOverlay extends StatelessWidget {
  final LiveEngineTick tick;
  final VoidCallback onEmergencyTokenUsed;

  const FocusOverlay({
    super.key,
    required this.tick,
    required this.onEmergencyTokenUsed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade900.withValues(alpha: 0.4),
                  border: Border.all(color: Colors.redAccent, width: 2),
                ),
                child: const Icon(Icons.shield_rounded, size: 72, color: Colors.redAccent),
              ),
              const SizedBox(height: 24),
              Text(
                tr.acessoBloqueadoPeloChronos,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                tr.oTempoDeTelaDiarioPara(tick.displayName),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pause_circle_filled, color: Colors.orangeAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr.reproducaoMprisPausadaAutomaticamente,
                            style: TextStyle(color: Colors.orange.shade200, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.screen_lock_rotation, color: Colors.orangeAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr.janelaSobrepostaAtivaEnquantoOApp,
                            style: TextStyle(color: Colors.orange.shade200, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (tick.emergencyTokensRemaining.toInt() > 0) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.emergency_share),
                  label: Text(tr.usarTokenDeEmergencia1hP0(tick.emergencyTokensRemaining)),
                  onPressed: () async {
                    final res = await consumeEmergencyToken(entityId: tick.entityId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res.message),
                          backgroundColor: res.success ? Colors.teal.shade700 : Colors.red.shade800,
                        ),
                      );
                    }
                    onEmergencyTokenUsed();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  tr.avisoConsumirUmTokenDeEmergencia,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tr.nenhumTokenDeEmergenciaRestantePara,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
