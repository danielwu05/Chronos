import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';

import '../src/rust/api/youtube.dart';

/// Edits user rules that assign a YouTube content type by channel or keyword
/// (e.g. "Flow Podcast" -> Podcasts, or a new type "Minecraft" by keyword).
class YoutubeCustomTypesDialog extends StatefulWidget {
  const YoutubeCustomTypesDialog({super.key});

  @override
  State<YoutubeCustomTypesDialog> createState() => _YoutubeCustomTypesDialogState();
}

class _RuleDraft {
  String typeId;
  final TextEditingController name;
  final TextEditingController channels;
  final TextEditingController keywords;

  _RuleDraft({required this.typeId, String name = '', String channels = '', String keywords = ''})
      : name = TextEditingController(text: name),
        channels = TextEditingController(text: channels),
        keywords = TextEditingController(text: keywords);
}

class _YoutubeCustomTypesDialogState extends State<YoutubeCustomTypesDialog> {
  static const _newType = '__new__';
  late final List<YtContentTypeDto> _builtin;
  final List<_RuleDraft> _rules = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _builtin = getYoutubeContentTypes().where((t) => !t.id.startsWith('custom_')).toList();
    for (final r in getYoutubeCustomRules()) {
      final isBuiltin = _builtin.any((b) => b.id == r.typeId);
      _rules.add(_RuleDraft(
        typeId: isBuiltin ? r.typeId : _newType,
        name: isBuiltin ? '' : r.name,
        channels: r.channels.join(', '),
        keywords: r.keywords.join(', '),
      ));
    }
  }

  List<String> _split(String raw) =>
      raw.split(RegExp(r'[,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  String _slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return 'custom_${s.isEmpty ? DateTime.now().millisecondsSinceEpoch : s}';
  }

  Future<void> _save() async {
    final out = <YtCustomRuleDto>[];
    for (final r in _rules) {
      final isNew = r.typeId == _newType;
      final name = r.name.text.trim();
      if (isNew && name.isEmpty) {
        setState(() => _error = tr.deUmNomeAoTipoNovo);
        return;
      }
      out.add(YtCustomRuleDto(
        typeId: isNew ? _slug(name) : r.typeId,
        name: isNew ? name : '',
        channels: _split(r.channels.text),
        keywords: _split(r.keywords.text),
      ));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await saveYoutubeCustomRules(rules: out);
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop();
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
      title: Text(tr.tiposDoYoutubePorCanalOu),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.exCanalFlowPodcastContaComo,
              style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rules.length,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (_, i) {
                  final r = _rules[i];
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: r.typeId,
                              decoration: InputDecoration(labelText: tr.tipo, isDense: true),
                              items: [
                                for (final t in _builtin) DropdownMenuItem(value: t.id, child: Text(t.label)),
                                DropdownMenuItem(value: _newType, child: Text(tr.novoTipo)),
                              ],
                              onChanged: (v) => setState(() => r.typeId = v ?? r.typeId),
                            ),
                          ),
                          if (r.typeId == _newType) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: r.name,
                                decoration: InputDecoration(labelText: tr.nomeDoTipo, isDense: true),
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: tr.remover,
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => setState(() => _rules.removeAt(i)),
                          ),
                        ],
                      ),
                      TextField(
                        controller: r.channels,
                        decoration: InputDecoration(labelText: tr.canais, isDense: true),
                      ),
                      TextField(
                        controller: r.keywords,
                        decoration: InputDecoration(labelText: tr.palavrasNoTituloTags, isDense: true),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tr.adicionarRegra),
              onPressed: () => setState(() => _rules.add(_RuleDraft(typeId: _builtin.isNotEmpty ? _builtin.first.id : _newType))),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(tr.cancelar)),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr.salvar)),
      ],
    );
  }
}
