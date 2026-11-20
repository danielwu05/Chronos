import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';

import '../services/browser_extension_installer.dart';
import '../services/chronos_guard_service.dart';
import '../src/rust/api/adult.dart';

/// Adult content filter: public adult-site list, forced SafeSearch and system-wide
/// family DNS (guard). Parental mode keeps it always on; anti-cheat forbids loosening.
class AdultFilterCard extends StatefulWidget {
  const AdultFilterCard({super.key});

  @override
  State<AdultFilterCard> createState() => _AdultFilterCardState();
}

class _AdultFilterCardState extends State<AdultFilterCard> {
  late AdultFilterDto _f;
  bool _busy = false;
  final _allowCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _f = getAdultFilter();
    _privateBlock = getPrivateBrowsingBlock();
    networkDnsFiltersAdult().then((v) {
      if (mounted) setState(() => _networkFilters = v);
    }).catchError((_) {});
  }

  /// The network's DNS (router/provider) already blocks adult sites.
  bool _networkFilters = false;

  late bool _privateBlock;

  /// Incognito/private windows + guest profiles (user or parents choose; anti-cheat
  /// forbids turning it off). Saved first, then applied by the root guard.
  Future<void> _setPrivateBlock(bool blocked) async {
    setState(() => _busy = true);
    final res = await setPrivateBrowsingBlock(blocked: blocked);
    String? err = res.success ? null : res.message;
    if (err == null) {
      err = await ChronosGuardService.applyPrivateBrowsingBlock(blocked);
      if (err != null) {
        // Guard refused (e.g. password cancelled): keep the saved choice in sync.
        await setPrivateBrowsingBlock(blocked: !blocked);
      }
    }
    if (!mounted) return;
    setState(() {
      _privateBlock = getPrivateBrowsingBlock();
      _busy = false;
    });
    // Unblocked without the extension allowed in incognito: Chrome only shows that
    // toggle now, so explain the grace window.
    if (err == null && !blocked && res.message.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr.permitaAExtensaoNoAnonimo),
          content: Text(res.message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openIncognitoPermission();
              },
              child: Text(tr.abrirNosNavegadores),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.entendi)),
          ],
        ),
      );
      return;
    }
    _snack(err ?? (blocked ? tr.guiaAnonimaBloqueadaNosNavegadores : tr.guiaAnonimaLiberada), err == null);
  }

  /// Opens the Chronos extension page in each Chromium browser so the user can turn on
  /// "Allow in Incognito" (Chrome has no policy for it).
  /// Opens the permission page only in browsers that still lack it: browsers that
  /// reported "allowed" are skipped; closed browsers (no report) are opened.
  Future<void> _openIncognitoPermission() async {
    var skip = <String>{};
    try {
      final acc = getIncognitoAccess();
      skip = acc.reportedBrowsers.where((b) => !acc.deniedBrowsers.contains(b)).toSet();
    } catch (_) {}
    final opened = await BrowserExtensionInstaller.openIncognitoPermissionPages(skip: skip);
    _snack(
      opened.isEmpty
          ? (skip.isNotEmpty ? tr.todosOsNavegadoresJaPermitemAnonimo : tr.nenhumNavegadorChromiumEncontrado)
          : tr.abertoEmP0(opened.join(', ')),
      opened.isNotEmpty || skip.isNotEmpty,
    );
  }

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.teal.shade700 : Colors.red.shade800,
    ));
  }

  static final bool _screenAiSupported = () {
    try {
      return screenAiSupported();
    } catch (_) {
      return false;
    }
  }();

  AdultFilterDto _copy({
    bool? enabled,
    bool? useDomainList,
    bool? safeSearch,
    bool? logAttempts,
    List<String>? allowlist,
    bool? dnsProtection,
    String? dnsProvider,
    bool? imageAi,
    bool? screenAi,
  }) =>
      AdultFilterDto(
        enabled: enabled ?? _f.enabled,
        useDomainList: useDomainList ?? _f.useDomainList,
        safeSearch: safeSearch ?? _f.safeSearch,
        logAttempts: logAttempts ?? _f.logAttempts,
        allowlist: allowlist ?? _f.allowlist,
        dnsProtection: dnsProtection ?? _f.dnsProtection,
        dnsProvider: dnsProvider ?? _f.dnsProvider,
        imageAi: imageAi ?? _f.imageAi,
        screenAi: screenAi ?? _f.screenAi,
        parentalForced: _f.parentalForced,
        domainListSize: _f.domainListSize,
      );

  Future<void> _save(AdultFilterDto next) async {
    setState(() => _busy = true);
    final res = await saveAdultFilter(filter: next);
    if (!res.success) {
      _snack(res.message, false);
    } else {
      // System-wide part (root guard): family DNS + browser SafeSearch policies.
      final saved = getAdultFilter();
      final provider = saved.enabled && saved.dnsProtection ? saved.dnsProvider : 'off';
      final err = await ChronosGuardService.applyFamilyDns(
        provider: provider,
        safeSearch: saved.enabled && saved.safeSearch,
      );
      _snack(err ?? res.message, err == null);
    }
    if (!mounted) return;
    setState(() {
      _f = getAdultFilter();
      _busy = false;
    });
  }

  /// Family DNS replaces the network's DNS for the whole computer: warn before enabling.
  Future<bool> _confirmDnsRisk() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.ativarProtecaoPorDns),
        content: Text(
          tr.oDnsFamiliaPassaAValer,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancelar)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr.entendiAtivar)),
        ],
      ),
    );
    return ok == true;
  }

  String _fmtTime(int utc) {
    final d = DateTime.fromMillisecondsSinceEpoch(utc * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final applied = ChronosGuardService.appliedFamilyDns();
    final attempts = _f.logAttempts ? getAdultAttempts(limit: 8) : const <AdultAttemptDto>[];
    final on = _f.enabled;

    Widget sw(String title, String sub, bool value, ValueChanged<bool>? onChanged) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(title, style: const TextStyle(fontSize: 14)),
          subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
          value: value,
          onChanged: _busy ? null : onChanged,
        );

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
                Icon(Icons.no_adult_content, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text(tr.filtroDeConteudoAdulto, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            if (_f.parentalForced)
              Text(tr.modoParentalOFiltroFicaSempre,
                  style: TextStyle(fontSize: 12, color: Colors.amberAccent))
            else
              sw(tr.ativarFiltro, tr.bloqueiaSitesAdultosComATela, on,
                  (v) => _save(_copy(enabled: v))),
            sw(
              tr.bloquearGuiaAnonimaEConvidado,
              tr.impedeJanelasAnonimasPrivadasEO(_f.parentalForced ? tr.escolhaDosPaisSuffix : ''),
              _privateBlock,
              _setPrivateBlock,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(tr.permitirAExtensaoNoAnonimoAbrir),
                onPressed: _openIncognitoPermission,
              ),
            ),
            Builder(builder: (_) {
              final acc = getIncognitoAccess();
              if (acc.browsers == 0) return const SizedBox.shrink();
              final ok = acc.denied == 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  ok
                      ? tr.extensaoPermitidaNoAnonimoEmP0(acc.browsers)
                      : tr.extensaoSemPermissaoNoAnonimoEm(acc.denied, acc.browsers, _privateBlock ? '' : tr.guiaAnonimaSeraBloqueadaSuffix),
                  style: TextStyle(fontSize: 12, color: ok ? Colors.white60 : Colors.amberAccent),
                ),
              );
            }),
            if (on && !_f.useDomainList && !_f.safeSearch && !_f.dnsProtection)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr.filtroLigadoMasNadaEstaBloqueando,
                        style: TextStyle(fontSize: 12, color: Colors.amberAccent),
                      ),
                    ),
                  ],
                ),
              ),
            if (on) ...[
              sw(
                tr.listaDeSitesAdultos,
                _f.domainListSize > 0 ? tr.p0SitesConhecidosAtualizaTodaSemana(_f.domainListSize) : tr.baixandoALista,
                _f.useDomainList,
                (v) => _save(_copy(useDomainList: v)),
              ),
              sw(
                tr.iaDeImagensLocal,
                tr.desfocaImagensAteUmModeloDe,
                _f.imageAi,
                (v) => _save(_copy(imageAi: v)),
              ),
              sw(
                tr.iaDeImagensNaTelaInteira,
                _screenAiSupported ? tr.iaTelaInteiraDescricao : tr.iaTelaInteiraNaoSuportada,
                _f.screenAi,
                (v) {
                  if (v && !_screenAiSupported) return;
                  _save(_copy(screenAi: v));
                },
              ),
              sw(tr.safesearchForcado, tr.googleBingEDuckduckgoEmModo,
                  _f.safeSearch, (v) => _save(_copy(safeSearch: v))),
              sw(
                tr.protecaoPorDnsComputadorInteiro,
                tr.usaUmDnsFamiliaEmTodo,
                _f.dnsProtection,
                (v) async {
                  if (v && !await _confirmDnsRisk()) return;
                  _save(_copy(dnsProtection: v));
                },
              ),
              if (_f.dnsProtection)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: DropdownButtonFormField<String>(
                    initialValue: _f.dnsProvider,
                    isDense: true,
                    decoration: InputDecoration(labelText: tr.servicoDeDnsFamilia, isDense: true),
                    items: [
                      for (final p in getDnsProviders()) DropdownMenuItem(value: p.id, child: Text(p.label)),
                    ],
                    onChanged: _busy ? null : (v) => _save(_copy(dnsProvider: v)),
                  ),
                ),
              Text(
                applied.provider == 'off'
                    ? (_networkFilters
                        ? tr.dnsDoChronosDesligadoMasO
                        : tr.dnsDoSistemaNormalSemDns)
                    : tr.dnsDoSistemaP0AtivoP1(applied.provider, applied.safeSearch ? tr.safesearchNosNavegadoresSuffix : ''),
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
              sw(
                tr.registrarTentativas,
                tr.anotaDataESiteDeCada(_f.parentalForced ? tr.escolhaDosPaisSuffix : ''),
                _f.logAttempts,
                (v) => _save(_copy(logAttempts: v)),
              ),
              if (attempts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tr.ultimasTentativas, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                for (final a in attempts)
                  Text('${_fmtTime(a.atUtc.toInt())} — ${a.site}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history, size: 16),
                    label: Text(tr.verHistoricoCompleto),
                    onPressed: () => showDialog<void>(context: context, builder: (_) => const _AttemptHistoryDialog()),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(tr.excecoesSitesNuncaBloqueadosPorEste,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Wrap(
                spacing: 6,
                children: [
                  for (final a in _f.allowlist)
                    InputChip(
                      label: Text(a),
                      onDeleted: _busy
                          ? null
                          : () => _save(_copy(allowlist: _f.allowlist.where((x) => x != a).toList())),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _allowCtl,
                      decoration: InputDecoration(hintText: tr.exSiteDaEscolaCom, isDense: true),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final v = _allowCtl.text.trim();
                            if (v.isEmpty) return;
                            _allowCtl.clear();
                            _save(_copy(allowlist: [..._f.allowlist, v]));
                          },
                    child: Text(tr.adicionar),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full attempt log with a period filter (today / 7 days / 30 days / all).
class _AttemptHistoryDialog extends StatefulWidget {
  const _AttemptHistoryDialog();

  @override
  State<_AttemptHistoryDialog> createState() => _AttemptHistoryDialogState();
}

class _AttemptHistoryDialogState extends State<_AttemptHistoryDialog> {
  static List<(String, int?)> get _periods => [(tr.hoje, 0), (tr.t7Dias, 7), (tr.t30Dias, 30), (tr.tudo, null)];
  int _period = 1;
  late final List<AdultAttemptDto> _all = getAdultAttempts(limit: 5000);

  static String _method(String m) => switch (m) {
        'lista' => tr.listaDeSites,
        'reddit' => tr.reddit,
        'imagem' => tr.iaDeImagens,
        'x' => 'X',
        _ => m,
      };

  @override
  Widget build(BuildContext context) {
    final days = _periods[_period].$2;
    final now = DateTime.now();
    final from = days == null
        ? null
        : DateTime(now.year, now.month, now.day).subtract(Duration(days: days == 0 ? 0 : days - 1));
    final items = _all.where((a) {
      if (from == null) return true;
      return DateTime.fromMillisecondsSinceEpoch(a.atUtc.toInt() * 1000).isAfter(from);
    }).toList();
    String two(int n) => n.toString().padLeft(2, '0');
    return AlertDialog(
      title: Text(tr.historicoDeTentativas),
      content: SizedBox(
        width: 520,
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
            Text(tr.p0TentativaS(items.length), style: const TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 4),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(tr.nenhumaTentativaNestePeriodo))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final a = items[i];
                        final d = DateTime.fromMillisecondsSinceEpoch(a.atUtc.toInt() * 1000);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.block, size: 18, color: Colors.redAccent),
                          title: Text(a.site, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)} • ${_method(a.method)}',
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
