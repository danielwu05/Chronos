import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';

import '../src/rust/api/holidays.dart';
import '../src/rust/api/simple.dart';

/// Holiday quotas: holiday > weekend > weekday. Shows national/custom holidays and
/// lets each rule have its own quota on holidays.
class HolidaysCard extends StatefulWidget {
  const HolidaysCard({super.key});

  @override
  State<HolidaysCard> createState() => _HolidaysCardState();
}

class _HolidaysCardState extends State<HolidaysCard> {
  List<HolidayDto> _custom = const [];
  bool _antiCheatActive = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    bool ac = false;
    try {
      ac = (await getAntiCheatState()).isActive;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _custom = getCustomHolidays();
      _antiCheatActive = ac;
    });
  }

  void _snack(ActionFeedback res) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.message),
      backgroundColor: res.success ? Colors.teal.shade700 : Colors.red.shade800,
    ));
  }

  String _fmtDate(String ymd) {
    final p = ymd.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : ymd;
  }

  Future<void> _addCustom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    final nameCtl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.nomeDoFeriado),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr.exFeriasAniversario),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.cancelar)),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtl.text), child: Text(tr.adicionar)),
        ],
      ),
    );
    if (name == null) return;
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    final next = [..._custom.where((h) => h.date != date), HolidayDto(date: date, name: name)];
    _snack(await saveCustomHolidays(holidays: next));
    await _reload();
  }

  Future<void> _removeCustom(HolidayDto h) async {
    _snack(await saveCustomHolidays(holidays: _custom.where((x) => x.date != h.date).toList()));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final today = getTodayHoliday();
    final upcoming = getUpcomingHolidays(limit: 5);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                Icon(Icons.celebration, color: Colors.orangeAccent, size: 20),
                SizedBox(width: 8),
                Text(tr.feriados, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              today != null
                  ? tr.hojeEFeriadoP0AsCotas(today)
                  : tr.aCotaDeFeriadoEDefinida,
              style: TextStyle(fontSize: 13, color: today != null ? Colors.orangeAccent : Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(tr.proximosFeriados, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            for (final h in upcoming)
              Text('${_fmtDate(h.date)} — ${h.name}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(tr.feriadosPersonalizados, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Tooltip(
                  message: _antiCheatActive
                      ? tr.comOAntiBurlaLigadoNao
                      : tr.adicionarUmaDataComACota,
                  child: TextButton.icon(
                    icon: Icon(_antiCheatActive ? Icons.lock : Icons.add, size: 16),
                    label: Text(tr.adicionarData),
                    onPressed: _antiCheatActive ? null : _addCustom,
                  ),
                ),
              ],
            ),
            if (_antiCheatActive)
              Text(
                tr.antiBurlaLigadoAdicionarFeriadosEsta,
                style: TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
            if (_custom.isEmpty)
              Text(tr.nenhum, style: TextStyle(fontSize: 12, color: Colors.white54)),
            for (final h in _custom)
              Row(
                children: [
                  Expanded(
                    child: Text('${_fmtDate(h.date)} — ${h.name}', style: const TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr.remover,
                    icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                    onPressed: () => _removeCustom(h),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
