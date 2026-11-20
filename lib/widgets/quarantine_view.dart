import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

class QuarantineView extends StatefulWidget {
  const QuarantineView({super.key});

  @override
  State<QuarantineView> createState() => _QuarantineViewState();
}

class _QuarantineViewState extends State<QuarantineView> {
  List<QuarantineItemDto> _items = [];
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _sortQuarantineList(List<QuarantineItemDto> list) {
    list.sort((a, b) {
      final aPending = a.status == 'QUARANTINED' ? 0 : 1;
      final bPending = b.status == 'QUARANTINED' ? 0 : 1;
      if (aPending != bPending) return aPending.compareTo(bPending);
      return b.requestedAtUtc.compareTo(a.requestedAtUtc);
    });
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final list = await getQuarantineItems();
      _sortQuarantineList(list);
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanSystem() async {
    setState(() => _scanning = true);
    try {
      final res = await scanSystemProcesses();
      _sortQuarantineList(res);
      if (mounted) {
        setState(() {
          _items = res;
          _scanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr.varreduraConcluidaP0ProcessosAuditadosQuarentena(res.length)),
            backgroundColor: Colors.teal.shade700,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _reviewItem(String reqId, bool approve) async {
    final res = await reviewQuarantineItem(requestId: reqId, approved: approve);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? Colors.teal.shade700 : Colors.red.shade800,
      ),
    );
    await _loadItems();
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return Colors.greenAccent;
      case 'REJECTED':
        return Colors.redAccent;
      case 'QUARANTINED':
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.inspecaoDeBinariosQuarentena,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      tr.protecaoContraBinariosNaoEmpacotadosPelo,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.radar, size: 18),
                label: Text(tr.escanearProcessos),
                onPressed: _scanning ? null : _scanSystem,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.teal.shade300),
                    const SizedBox(height: 16),
                    Text(
                      tr.nenhumProcessoNaoConfiavelEmQuarentena,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr.cliqueEmEscanearProcessosParaAuditar,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final statusColor = _getStatusColor(item.status);

                  return Card(
                    color: Colors.grey.shade900,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.terminal, color: statusColor, size: 32),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: statusColor, width: 0.8),
                                      ),
                                      child: Text(
                                        item.status,
                                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.appIdentifier,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (item.status == 'QUARANTINED') ...[
                            IconButton(
                              tooltip: tr.aprovarBinario,
                              icon: const Icon(Icons.check, color: Colors.greenAccent),
                              onPressed: () => _reviewItem(item.requestId, true),
                            ),
                            IconButton(
                              tooltip: tr.rejeitarBloquear,
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () => _reviewItem(item.requestId, false),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
