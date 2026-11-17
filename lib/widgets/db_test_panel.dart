import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

class DbTestPanel extends StatefulWidget {
  final String activeEntityId;
  final VoidCallback onDbChanged;
  final VoidCallback? onResetOnboarding;

  const DbTestPanel({
    super.key,
    required this.activeEntityId,
    required this.onDbChanged,
    this.onResetOnboarding,
  });

  @override
  State<DbTestPanel> createState() => _DbTestPanelState();
}

class _DbTestPanelState extends State<DbTestPanel> {
  DatabaseStatsDto? _stats;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    setState(() => _loading = true);
    try {
      final s = await getDatabaseStats();
      if (mounted) {
        setState(() {
          _stats = s;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showFeedback(ActionFeedback fb) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fb.message),
        backgroundColor: fb.success ? Colors.teal.shade700 : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleResetFull() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Reiniciar Banco de Dados?'),
          ],
        ),
        content: const Text(
          'Esta ação irá apagar todos os intervalos de consumo gravados, '
          'remover itens de quarentena, redefinir regras para o estado padrão '
          'e restaurar todos os tokens de emergência.\n\n'
          'Deseja prosseguir com o reset completo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, Resetar Tudo'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await resetDatabaseFull();
    _showFeedback(res);
    await _refreshStats();
    widget.onDbChanged();
  }

  Future<void> _handleResetDaily() async {
    final res = await resetDailyUsage();
    _showFeedback(res);
    await _refreshStats();
    widget.onDbChanged();
  }

  Future<void> _handleUnlockRatchet() async {
    final res = await debugUnlockRatchet(entityId: widget.activeEntityId);
    _showFeedback(res);
    await _refreshStats();
    widget.onDbChanged();
  }

  Future<void> _handleRefillTokens() async {
    final res = await refillEmergencyTokens();
    _showFeedback(res);
    await _refreshStats();
    widget.onDbChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.4), width: 1),
      ),
      color: Colors.amber.shade900.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined, color: Colors.amber.shade300, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Painel de Testes & Manutenção do SQLite',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade200,
                        ),
                      ),
                      Text(
                        'Ferramentas de depuração de tempo de tela, catraca e persistência WAL',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar estatísticas do banco',
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _refreshStats,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_stats != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatBadge(
                      label: 'Regras',
                      value: '${_stats!.totalRules}',
                      icon: Icons.rule,
                    ),
                    _StatBadge(
                      label: 'Intervalos SQLite',
                      value: '${_stats!.totalIntervals}',
                      icon: Icons.timer,
                    ),
                    _StatBadge(
                      label: 'Quarentena',
                      value: '${_stats!.totalQuarantineItems}',
                      icon: Icons.security,
                    ),
                    _StatBadge(
                      label: 'Tokens Mês',
                      value: '${_stats!.emergencyTokens}/2',
                      icon: Icons.vpn_key,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reiniciar Banco Completo'),
                  onPressed: _handleResetFull,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.history_toggle_off, size: 18),
                  label: const Text('Zerar Consumo Diário'),
                  onPressed: _handleResetDaily,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade900,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: Text('Destravar Catraca (${widget.activeEntityId})'),
                  onPressed: _handleUnlockRatchet,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple.shade200,
                    side: BorderSide(color: Colors.purple.shade400),
                  ),
                  icon: const Icon(Icons.token, size: 18),
                  label: const Text('Recarregar Tokens (+2)'),
                  onPressed: _handleRefillTokens,
                ),
                if (widget.onResetOnboarding != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                    ),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Refazer Cadastro / Trocar Modo'),
                    onPressed: () async {
                      final res = await resetOnboardingState();
                      _showFeedback(res);
                      widget.onResetOnboarding!();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.amber.shade300),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
  }
}
