import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';

import '../src/rust/api/tamper.dart';

/// Layered anti-cheat: tampering attempts caught by the root vault (database edits,
/// stopped daemon, removed autostart, clock changes) and the chosen reaction.
class TamperLogCard extends StatefulWidget {
  const TamperLogCard({super.key});

  @override
  State<TamperLogCard> createState() => _TamperLogCardState();
}

class _TamperLogCardState extends State<TamperLogCard> {
  late String _reaction;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reaction = _safe(getTamperReaction, 'restore');
  }

  static T _safe<T>(T Function() f, T fallback) {
    try {
      return f();
    } catch (_) {
      return fallback;
    }
  }

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.teal.shade700 : Colors.red.shade800,
    ));
  }

  Future<void> _setReaction(String value) async {
    setState(() => _busy = true);
    final res = await setTamperReaction(reaction: value);
    _snack(res.message, res.success);
    if (!mounted) return;
    setState(() {
      _reaction = _safe(getTamperReaction, _reaction);
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _safe(
      getVaultStatus,
      const VaultStatusDto(installed: false, clockOffsetSeconds: 0, penaltyUntilUtc: 0),
    );
    final events = _safe(() => getTamperEvents(limit: 8), const <TamperEventDto>[]);
    final penaltyUntil = status.penaltyUntilUtc.toInt();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      color: isDark ? const Color(0xFF161922) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gpp_maybe_outlined, color: Colors.orangeAccent, size: 20),
                SizedBox(width: 8),
                Text(tr.registroDeBurlas, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              status.installed
                  ? tr.cofreDoChronosAtivoComO
                  : tr.cofreDoChronosNaoInstaladoInstale,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (status.clockOffsetSeconds.toInt().abs() > 60)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr.relogioDoSistemaCorrigidoEmP0((status.clockOffsetSeconds.toInt() / 60).round()),
                  style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                ),
              ),
            if (penaltyUntil > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr.penalidadeAtivaTodasAsSessoesBloqueadas(_fmt(penaltyUntil, withDate: false)),
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 10),
            Text(tr.aoDetectarUmaBurla, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            RadioGroup<String>(
              groupValue: _reaction,
              onChanged: (v) {
                if (_busy || v == null || v == _reaction) return;
                _setReaction(v);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: 'restore',
                    title: Text(tr.restaurarERegistrar, style: TextStyle(fontSize: 13)),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: 'restore_penalty',
                    title: Text(tr.restaurarRegistrarEBloquearTudoAte, style: TextStyle(fontSize: 13)),
                    subtitle: Text(tr.comOAntiBurlaAtivoNao,
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (events.isEmpty)
              Text(tr.nenhumaTentativaDeBurlaRegistrada, style: TextStyle(fontSize: 12, color: Colors.white60))
            else ...[
              Text(tr.ultimasTentativas, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              for (final e in events)
                Text('${_fmt(e.atUtc.toInt())} — ${_kind(e.kind)}: ${e.detail}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(tr.verHistoricoCompleto),
                  onPressed: () => showDialog<void>(context: context, builder: (_) => const _TamperHistoryDialog()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _fmt(int utc, {bool withDate = true}) {
  final d = DateTime.fromMillisecondsSinceEpoch(utc * 1000);
  final time = '${_two(d.hour)}:${_two(d.minute)}';
  return withDate ? '${_two(d.day)}/${_two(d.month)} $time' : time;
}

String _kind(String k) => switch (k) {
      'db_edit' => tr.bancoEditado,
      'db_deleted' => tr.bancoApagado,
      'daemon_stopped' => tr.servicoParado,
      'daemon_unit_removed' => tr.servicoApagado,
      'autostart_removed' => tr.autostartApagado,
      'clock_changed' => tr.relogioAlterado,
      'unlock_failed' => tr.desbloqueioRecusado,
      _ => k,
    };

class _TamperHistoryDialog extends StatefulWidget {
  const _TamperHistoryDialog();

  @override
  State<_TamperHistoryDialog> createState() => _TamperHistoryDialogState();
}

class _TamperHistoryDialogState extends State<_TamperHistoryDialog> {
  static List<(String, int?)> get _periods => [(tr.hoje, 0), (tr.t7Dias, 7), (tr.t30Dias, 30), (tr.tudo, null)];
  int _period = 1;
  late final List<TamperEventDto> _all = () {
    try {
      return getTamperEvents(limit: 5000);
    } catch (_) {
      return const <TamperEventDto>[];
    }
  }();

  @override
  Widget build(BuildContext context) {
    final days = _periods[_period].$2;
    final now = DateTime.now();
    final from = days == null
        ? null
        : DateTime(now.year, now.month, now.day).subtract(Duration(days: days == 0 ? 0 : days - 1));
    final items = _all
        .where((e) => from == null || DateTime.fromMillisecondsSinceEpoch(e.atUtc.toInt() * 1000).isAfter(from))
        .toList();
    return AlertDialog(
      title: Text(tr.historicoDeBurlas),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _periods.length; i++)
                  ChoiceChip(
                    label: Text(_periods[i].$1),
                    selected: _period == i,
                    onSelected: (_) => setState(() => _period = i),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr.p0EventoS(items.length), style: const TextStyle(fontSize: 12, color: Colors.white60)),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(tr.nenhumaBurlaNestePeriodo))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final e = items[i];
                        final d = DateTime.fromMillisecondsSinceEpoch(e.atUtc.toInt() * 1000);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.gpp_bad_outlined, size: 18, color: Colors.orangeAccent),
                          title: Text(_kind(e.kind), style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)} • ${e.detail}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.fechar))],
    );
  }
}
