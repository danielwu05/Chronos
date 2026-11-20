import 'package:flutter/material.dart';

import '../services/app_locale.dart';
import '../src/rust/api/simple.dart';

/// List of the user's own challenge texts (they replace the built-in ones), with an
/// optional "too easy" check.
class ChallengeTextsDialog extends StatefulWidget {
  const ChallengeTextsDialog({super.key});

  @override
  State<ChallengeTextsDialog> createState() => _ChallengeTextsDialogState();
}

class _ChallengeTextsDialogState extends State<ChallengeTextsDialog> {
  static const _minChars = 120;

  late final List<String> _texts = List.of(getCustomChallengeTexts());
  late bool _check = getChallengeStrengthCheck();
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  List<String> _issues(String t) => _check ? analyzeChallengeText(text: t) : const [];

  Future<void> _edit({int? index}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ChallengeTextEditor(initial: index == null ? '' : _texts[index], check: _check),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _texts.add(result);
      } else {
        _texts[index] = result;
      }
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _toggleCheck(bool v) async {
    final res = await setChallengeStrengthCheck(enabled: v);
    if (!mounted) return;
    setState(() {
      if (res.success) {
        _check = v;
      } else {
        _error = res.message;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await setCustomChallengeTexts(texts: _texts);
    if (!mounted) return;
    if (res.success) {
      Navigator.pop(context, res.message);
    } else {
      setState(() {
        _saving = false;
        _error = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr.textosDoDesafio),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.textosDesafioExplicacao, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(tr.recusarTextosFaceis, style: const TextStyle(fontSize: 14)),
              subtitle: Text(tr.recusarTextosFaceisDescricao, style: const TextStyle(fontSize: 12)),
              value: _check,
              onChanged: _toggleCheck,
            ),
            const Divider(),
            if (_texts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr.semTextosUsaOsPadrao, style: const TextStyle(fontSize: 13, color: Colors.white60)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _texts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _texts[i];
                    final issues = _issues(t);
                    final short = t.length < _minChars;
                    final bad = short || issues.isNotEmpty;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(bad ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                          color: bad ? Colors.orangeAccent : Colors.tealAccent),
                      title: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        [tr.p0Caracteres(t.length), if (issues.isNotEmpty) issues.first].join(' • '),
                        style: TextStyle(fontSize: 11, color: bad ? Colors.orangeAccent : Colors.white54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _edit(index: i)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => setState(() {
                              _texts.removeAt(i);
                              _dirty = true;
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr.adicionarTexto),
              onPressed: () => _edit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancelar)),
        FilledButton(onPressed: !_dirty || _saving ? null : _save, child: Text(tr.salvar)),
      ],
    );
  }
}

/// Editor of one text, with a live character count and the "too easy" reasons.
class _ChallengeTextEditor extends StatefulWidget {
  final String initial;
  final bool check;

  const _ChallengeTextEditor({required this.initial, required this.check});

  @override
  State<_ChallengeTextEditor> createState() => _ChallengeTextEditorState();
}

class _ChallengeTextEditorState extends State<_ChallengeTextEditor> {
  late final _ctl = TextEditingController(text: widget.initial);
  List<String> _issues = const [];

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _analyze() {
    final t = _ctl.text.trim();
    setState(() {
      _issues = t.isEmpty ? const [] : analyzeChallengeText(text: t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _ctl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = t.length < _ChallengeTextsDialogState._minChars;
    // Without the check only the minimum length is required.
    final blocking = widget.check ? _issues : (short ? _issues.take(1).toList() : const <String>[]);
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? tr.adicionarTexto : tr.editarTexto),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctl,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              onChanged: (_) => _analyze(),
              decoration: InputDecoration(border: const OutlineInputBorder(), hintText: tr.seuTextoAqui),
            ),
            const SizedBox(height: 6),
            Text(
              tr.p0Caracteres(t.length),
              style: TextStyle(fontSize: 12, color: short ? Colors.orangeAccent : Colors.white60),
            ),
            for (final issue in (widget.check ? _issues : const <String>[]))
              Text('• $issue', style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
            if (t.isNotEmpty && blocking.isEmpty && !short)
              Text(tr.textoAprovado, style: const TextStyle(fontSize: 12, color: Colors.tealAccent)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancelar)),
        FilledButton(
          onPressed: t.isEmpty || short || blocking.isNotEmpty ? null : () => Navigator.pop(context, t),
          child: Text(tr.ok),
        ),
      ],
    );
  }
}
