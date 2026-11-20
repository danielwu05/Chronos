import 'package:chronos_app/services/app_locale.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:chronos_app/services/web_block_server.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/src/rust/api/holidays.dart';
import 'package:chronos_app/src/rust/api/youtube.dart' show getYoutubeContentTypes;
import 'package:chronos_app/widgets/add_block_dialog.dart';
import 'package:chronos_app/widgets/anti_cheat_dialog.dart';
import 'package:chronos_app/widgets/browser_protection_panel.dart';

class RuleAppItem {
  final dynamic raw;
  final String name;
  const RuleAppItem(this.raw, this.name);
}

class RulesView extends StatefulWidget {
  final String activeEntityId;
  final ValueChanged<String> onSelectEntity;
  final VoidCallback onRulesUpdated;

  const RulesView({
    super.key,
    required this.activeEntityId,
    required this.onSelectEntity,
    required this.onRulesUpdated,
  });

  @override
  State<RulesView> createState() => _RulesViewState();
}

class _RulesViewState extends State<RulesView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RuleItemDto> _rules = [];
  List<WhitelistGroupDto> _whitelistGroups = [];
  final Set<String> _expandedRuleIds = {};
  final Set<String> _expandedWhitelistIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final rules = await getAllRules().timeout(const Duration(seconds: 4), onTimeout: () => _rules);
      final wl = await getAllWhitelistGroups().timeout(const Duration(seconds: 4), onTimeout: () => _whitelistGroups);
      if (mounted) {
        setState(() {
          _rules = rules;
          _whitelistGroups = wl;
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
      ),
    );
  }

  Future<bool> _ensureAntiCheatAllowed(String actionName) async {
    final state = await getAntiCheatState();
    if (state.isActive) {
      if (!mounted) return false;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E222D),
          title: Row(
            children: [
              Icon(
                state.mode == 'NUKE' ? Icons.warning_amber_rounded : Icons.shield_rounded,
                color: state.mode == 'NUKE' ? Colors.deepOrange : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(tr.modoAntiCheatAtivo),
            ],
          ),
          content: Text(
            state.mode == 'NUKE'
                ? tr.oChronosEstaNoModoNuke(state.nukeRemainingSeconds ~/ 60, actionName)
                : tr.naoEPermitidoP0EnquantoO(actionName),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr.entendido),
            ),
            if (state.mode == 'CHALLENGE')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
                icon: const Icon(Icons.lock_open, size: 16),
                label: Text(tr.resolverDesafio),
                onPressed: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (c) => AntiCheatDialog(
                      onStateChanged: () {
                        _loadAll();
                        widget.onRulesUpdated();
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _toggleBlock(String entityId, bool current) async {
    if (current) {
      final allowed = await _ensureAntiCheatAllowed(tr.desbloquearEntidades);
      if (!allowed) return;
    }
    final res = await toggleEntityBlock(entityId: entityId, blocked: !current);
    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _deleteRule(String entityId) async {
    final allowed = await _ensureAntiCheatAllowed(tr.removerRegrasDeBloqueio);
    if (!allowed) return;
    final res = await deleteRule(entityId: entityId);
    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _editRuleTime(RuleItemDto rule) async {
    final allowed = await _ensureAntiCheatAllowed(tr.editarTempoDeBloqueioEAgendamento);
    if (!allowed || !mounted) return;

    final result = await AddBlockDialog.show(
      context,
      initialRule: rule,
      dialogMode: BlockDialogMode.timeOnly,
    );
    if (result == null) return;

    final res = await saveRule(
      entityId: result.entityId,
      displayName: result.displayName,
      dailyQuotaSeconds: result.dailyQuotaSeconds,
      mode: result.mode,
      targetType: result.targetType,
      pattern: result.pattern,
      weekendQuotaSeconds: result.weekendQuotaSeconds,
      scheduleJson: result.scheduleJson,
    );

    if (result.isCompletelyBlocked) {
      await toggleEntityBlock(entityId: result.entityId, blocked: true);
    }

    _showFeedback(await _applyHolidayQuota(res, result));
    await _loadAll();
    widget.onRulesUpdated();
  }

  List<HolidayQuotaDto> _holidayQuotasSafe() {
    try {
      return getHolidayQuotas();
    } catch (_) {
      return const [];
    }
  }

  String _ruleQuotaSummary(RuleItemDto rule) {
    final extras = <String>[
      if (rule.weekendQuotaSeconds != null && rule.weekendQuotaSeconds! > 0)
        tr.finsDeSemanaP0(_formatSeconds(rule.weekendQuotaSeconds!)),
      for (final hq in _holidayQuotasSafe())
        if (hq.entityId == rule.entityId && hq.seconds > 0) 'Feriados: ${_formatSeconds(hq.seconds.toInt())}',
    ];
    final extra = extras.isEmpty ? '' : ' (${extras.join(', ')})';
    return tr.tempoDeTelaP0P1P2(_formatSeconds(rule.dailyQuotaSeconds), extra, _formatPatternSummary(rule.pattern, rule.entityId));
  }

  /// Holiday quota lives beside the rule (holiday > weekend > weekday). Saved only
  /// after the rule itself saved; anti-cheat refusals are reported like rule errors.
  Future<ActionFeedback> _applyHolidayQuota(ActionFeedback ruleRes, BlockConfigResult result) async {
    if (!ruleRes.success) return ruleRes;
    final hq = await setHolidayQuota(entityId: result.entityId, seconds: result.holidayQuotaSeconds);
    return hq.success ? ruleRes : hq;
  }

  /// Renaming is the only group change allowed while anti-cheat is active.
  Future<void> _renameRule(RuleItemDto rule) async {
    final ctl = TextEditingController(text: rule.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.renomear),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr.nome),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.cancelar)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr.salvar)),
        ],
      ),
    );
    ctl.dispose();
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || clean == rule.displayName) return;
    final res = await saveRule(
      entityId: rule.entityId,
      displayName: clean,
      dailyQuotaSeconds: rule.dailyQuotaSeconds,
      mode: rule.mode,
      targetType: rule.targetType,
      pattern: rule.pattern,
      weekendQuotaSeconds: rule.weekendQuotaSeconds,
      scheduleJson: rule.scheduleJson,
    );
    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _addAppsToRule(RuleItemDto rule) async {
    // Anti-cheat: groups can only be renamed.
    final allowed = await _ensureAntiCheatAllowed(tr.adicionarAppsOuSitesAoGrupo);
    if (!allowed || !mounted) return;
    final result = await AddBlockDialog.show(
      context,
      initialRule: rule,
      dialogMode: BlockDialogMode.appsOnly,
    );
    if (result == null) return;

    final res = await saveRule(
      entityId: result.entityId,
      displayName: result.displayName,
      dailyQuotaSeconds: result.dailyQuotaSeconds,
      mode: result.mode,
      targetType: result.targetType,
      pattern: result.pattern,
      weekendQuotaSeconds: result.weekendQuotaSeconds,
      scheduleJson: result.scheduleJson,
    );

    if (result.isCompletelyBlocked) {
      await toggleEntityBlock(entityId: result.entityId, blocked: true);
    }

    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _openAddRuleDialog() async {
    final result = await AddBlockDialog.show(context);
    if (result == null) return;

    final res = await saveRule(
      entityId: result.entityId,
      displayName: result.displayName,
      dailyQuotaSeconds: result.dailyQuotaSeconds,
      mode: result.mode,
      targetType: result.targetType,
      pattern: result.pattern,
      weekendQuotaSeconds: result.weekendQuotaSeconds,
      scheduleJson: result.scheduleJson,
    );

    if (result.isCompletelyBlocked) {
      await toggleEntityBlock(entityId: result.entityId, blocked: true);
    }

    _showFeedback(await _applyHolidayQuota(res, result));
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _openAddWhitelistDialog([WhitelistGroupDto? initial]) async {
    final allowed = await _ensureAntiCheatAllowed(
      initial != null ? tr.editarGruposDeListaBranca : tr.adicionarGruposDeListaBranca,
    );
    if (!allowed) return;

    if (!mounted) return;
    final res = await AddBlockDialog.show(
      context,
      isWhitelist: true,
      initialWhitelistGroup: initial,
    );
    if (res != null) {
      await _loadAll();
      widget.onRulesUpdated();
    }
  }

  Future<void> _deleteWhitelist(String groupId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.removerGrupoDeListaBranca),
        content: Text(
          tr.desejaRealmenteRemoverEsteGrupoDe,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr.cancelar),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr.remover),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final res = await deleteWhitelistGroup(groupId: groupId);
    _showFeedback(res);
    _loadAll();
  }

  String _cleanAppName(dynamic item) {
    if (item == null) return '';
    if (item is Map) {
      final name = item['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
      final exec = item['exec']?.toString().trim() ?? '';
      return _cleanExecutableName(exec);
    }
    final str = item.toString().trim();
    if (str.startsWith('{') && str.endsWith('}')) {
      try {
        final m = jsonDecode(str);
        if (m is Map && m['name'] != null) return m['name'].toString().trim();
      } catch (_) {}
    }
    if (str.contains('(')) {
      final beforeParen = str.split('(').first.trim();
      if (beforeParen.isNotEmpty) return beforeParen;
    }
    return _cleanExecutableName(str);
  }

  String _cleanExecutableName(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (s.contains('/')) {
      s = s.split('/').last.trim();
    }
    s = s.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\.desktop$', caseSensitive: false), '');
    if (s.isNotEmpty && s == s.toLowerCase()) {
      s = s[0].toUpperCase() + s.substring(1);
    }
    return s;
  }

  Future<void> _removeAppFromRule(RuleItemDto rule, dynamic rawAppItem, String appDisplayName) async {
    final allowed = await _ensureAntiCheatAllowed(tr.removerAplicativoDoGrupoDeBloqueio);
    if (!allowed) return;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.removerDoGrupoDeBloqueio),
        content: Text(tr.desejaRealmenteRemoverP0DesteGrupo(appDisplayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr.cancelar),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr.remover),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final pattern = rule.pattern.trim();
      Map<String, dynamic> patternMap = {};
      if (pattern.startsWith('{')) {
        patternMap = Map<String, dynamic>.from(jsonDecode(pattern) as Map);
      } else {
        patternMap = {'apps': pattern.split(',').map((e) => e.trim()).toList(), 'sites': []};
      }

      final appsList = (patternMap['apps'] as List?)?.toList() ?? [];
      appsList.removeWhere((item) {
        if (item == rawAppItem) return true;
        if (_cleanAppName(item) == appDisplayName) return true;
        if (item is Map && rawAppItem is Map && item['exec'] == rawAppItem['exec']) return true;
        return false;
      });
      patternMap['apps'] = appsList;
      final newPattern = jsonEncode(patternMap);

      final res = await saveRule(
        entityId: rule.entityId,
        displayName: rule.displayName,
        dailyQuotaSeconds: rule.dailyQuotaSeconds,
        mode: rule.mode,
        targetType: rule.targetType,
        pattern: newPattern,
        weekendQuotaSeconds: rule.weekendQuotaSeconds,
        scheduleJson: rule.scheduleJson,
      );

      _showFeedback(res);
      await _loadAll();
      widget.onRulesUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.erroAoRemoverAplicativoP0(e)), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _removeAppFromWhitelist(WhitelistGroupDto group, dynamic rawAppItem, String appDisplayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.removerDaListaBranca),
        content: Text(tr.desejaRemoverP0DestaListaBranca(appDisplayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr.cancelar),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr.remover),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final items = group.items.trim();
      Map<String, dynamic> itemsMap = {};
      if (items.startsWith('{')) {
        itemsMap = Map<String, dynamic>.from(jsonDecode(items) as Map);
      } else {
        itemsMap = {'apps': items.split(',').map((e) => e.trim()).toList(), 'sites': []};
      }

      final appsList = (itemsMap['apps'] as List?)?.toList() ?? [];
      appsList.removeWhere((item) {
        if (item == rawAppItem) return true;
        if (_cleanAppName(item) == appDisplayName) return true;
        if (item is Map && rawAppItem is Map && item['exec'] == rawAppItem['exec']) return true;
        return false;
      });
      itemsMap['apps'] = appsList;
      final newItems = jsonEncode(itemsMap);

      final res = await saveWhitelistGroup(
        groupId: group.groupId,
        displayName: group.displayName,
        items: newItems,
      );

      _showFeedback(res);
      await _loadAll();
      widget.onRulesUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.erroAoRemoverDaListaBranca(e)), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _formatSeconds(int s) {
    if (s <= 0) return tr.t0mBloqueioTotal;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return tr.p0HP1M(h, m);
    return '${m}m';
  }

  (List<RuleAppItem>, List<String>) _parseRuleAppsAndSites(RuleItemDto rule) {
    final pattern = rule.pattern.trim();
    if (pattern.startsWith('{')) {
      try {
        final decoded = jsonDecode(pattern);
        if (decoded is Map) {
          final rawApps = decoded['apps'] as List? ?? [];
          final apps = <RuleAppItem>[];
          for (final a in rawApps) {
            final clean = _cleanAppName(a);
            if (clean.isNotEmpty) {
              apps.add(RuleAppItem(a, clean));
            }
          }
          final sites = (decoded['sites'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? <String>[];
          return (apps, sites);
        }
      } catch (_) {}
    }

    final items = pattern.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final t = rule.targetType.toUpperCase();
    if (t == 'SITE' || t == 'SITE_GROUP' || t == 'KEYWORD') {
      return (<RuleAppItem>[], items);
    }
    final appItems = items.map((i) => RuleAppItem(i, _cleanAppName(i))).toList();
    return (appItems, <String>[]);
  }

  /// Labels of the YouTube content types allowed by a whitelist group ("Educacional", ...).
  List<String> _whitelistYoutubeTypeLabels(WhitelistGroupDto group) {
    final items = group.items.trim();
    if (!items.startsWith('{')) return const [];
    Map<String, String> labels = const {};
    try {
      labels = {for (final t in getYoutubeContentTypes()) t.id: t.label};
    } catch (_) {}
    try {
      final decoded = jsonDecode(items);
      if (decoded is Map && decoded['yt_types'] is List) {
        return [
          for (final t in decoded['yt_types'] as List)
            if ((t is Map ? t['type'] : t)?.toString().trim().isNotEmpty == true)
              labels[(t is Map ? t['type'] : t).toString()] ?? (t is Map ? t['type'] : t).toString(),
        ];
      }
    } catch (_) {}
    return const [];
  }

  int _whitelistYoutubeTypeCount(WhitelistGroupDto group) {
    final items = group.items.trim();
    if (!items.startsWith('{')) return 0;
    try {
      final decoded = jsonDecode(items);
      if (decoded is Map && decoded['yt_types'] is List) return (decoded['yt_types'] as List).length;
    } catch (_) {}
    return 0;
  }

  (List<RuleAppItem>, List<String>) _parseWhitelistAppsAndSites(WhitelistGroupDto group) {
    final items = group.items.trim();
    if (items.startsWith('{')) {
      try {
        final decoded = jsonDecode(items);
        if (decoded is Map) {
          final rawApps = decoded['apps'] as List? ?? [];
          final apps = <RuleAppItem>[];
          for (final a in rawApps) {
            final clean = _cleanAppName(a);
            if (clean.isNotEmpty) {
              apps.add(RuleAppItem(a, clean));
            }
          }
          final sites = (decoded['sites'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? <String>[];
          return (apps, sites);
        }
      } catch (_) {}
    }

    final list = items.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final apps = <RuleAppItem>[];
    final sites = <String>[];
    for (final clean in list) {
      if (clean.contains('.') && !clean.endsWith('.exe')) {
        sites.add(clean);
      } else {
        apps.add(RuleAppItem(clean, _cleanAppName(clean)));
      }
    }
    return (apps, sites);
  }

  String _formatPatternSummary(String pattern, String entityId) {
    if (pattern.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(pattern);
        if (decoded is Map) {
          final apps = (decoded['apps'] as List?)?.cast<String>() ?? [];
          final sites = (decoded['sites'] as List?)?.cast<String>() ?? [];
          final parts = <String>[];
          if (apps.isNotEmpty) parts.add(tr.p0AplicativoS(apps.length));
          if (sites.isNotEmpty) parts.add(tr.p0SiteSPalavraS(sites.length));
          if (parts.isNotEmpty) return parts.join(' • ');
        }
      } catch (_) {}
    }
    return pattern.isNotEmpty ? pattern : entityId;
  }

  String? _extractTimeWindowBadge(String? scheduleJson) {
    if (scheduleJson == null || scheduleJson.trim().isEmpty) return null;
    try {
      final map = jsonDecode(scheduleJson);
      if (map is Map && map['time_window_enabled'] == true) {
        final start = map['time_window_start'] ?? '08:00';
        final end = map['time_window_end'] ?? '18:00';
        final mode = map['time_window_mode'] == 'ALLOW_INSIDE' ? tr.permitirSomente : tr.bloquear;
        return tr.janelaP0P1P2(mode, start, end);
      }
    } catch (_) {}
    return null;
  }

  IconData _getIconForType(String targetType) {
    switch (targetType.toUpperCase()) {
      case 'GROUP':
        return Icons.sports_esports;
      case 'SITE_GROUP':
      case 'SITE':
        return Icons.public;
      case 'KEYWORD':
        return Icons.key;
      case 'APP':
      default:
        return Icons.apps;
    }
  }

  Color _getColorForType(String targetType) {
    switch (targetType.toUpperCase()) {
      case 'GROUP':
        return Colors.purpleAccent;
      case 'SITE_GROUP':
      case 'SITE':
        return Colors.blueAccent;
      case 'KEYWORD':
        return Colors.orangeAccent;
      case 'APP':
      default:
        return Colors.tealAccent;
    }
  }

  Future<void> _showExtensionDialog() async {
    var browsers = await BrowserExtensionInstaller.detectInstalledBrowsers();
    var guardStatus = await ChronosGuardService.checkStatus();
    if (!mounted) return;

    void showSnack(String msg, bool ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok ? Colors.teal.shade700 : Colors.red.shade800,
        ),
      );
    }

    var installing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> refreshDialog() async {
            final updatedBrowsers = await BrowserExtensionInstaller.detectInstalledBrowsers();
            final updatedGuard = await ChronosGuardService.checkStatus();
            if (ctx.mounted) {
              setDialogState(() {
                browsers = updatedBrowsers;
                guardStatus = updatedGuard;
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.extension, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(tr.extensaoProtecaoDosNavegadores),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.oChronosAplicaAExtensaoEm,
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    BrowserSetupFlowStepper(
                      hasPackages: browsers.isNotEmpty || guardStatus.isInstalled,
                      guardStatus: guardStatus,
                      browsers: browsers,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr.navegadoresInstaladosDetectadosP0(browsers.length),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.tealAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BrowserStatusChipsWrap(
                      browsers: browsers,
                      onFeedback: showSnack,
                      onRequestRelaunch: (browser) async {
                        await showConfirmRelaunchBrowsersDialog(
                          ctx,
                          [browser],
                          onCompleted: refreshDialog,
                          onFeedback: showSnack,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.tealAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          tr.servidorLocalAtivoNaPortaP0(WebBlockServer.port),
                          style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ManualBrowserFallbackTile(
                      browsers: browsers,
                      onFeedback: showSnack,
                      onShowChromeGuide: () async {
                        final path = BrowserExtensionInstaller.getCanonicalExtensionDir();
                        await Clipboard.setData(ClipboardData(text: path));
                        await BrowserExtensionInstaller.launchGoogleChromeWithExtensionGuide();
                        showSnack(
                          tr.chromeAbertoEmChromeExtensionsCole,
                          true,
                        );
                      },
                      onShowFirefoxGuide: () async {
                        await BrowserExtensionInstaller.launchFirefoxWithExtensionGuide();
                        showSnack(
                          tr.firefoxAbertoEmAboutPoliciesPara,
                          true,
                        );
                      },
                      onShowGuardTerminal: () async {
                        final launched = await ChronosGuardService.launchInstallerInTerminal();
                        if (launched) {
                          showSnack(tr.terminalAbertoParaAutorizacaoDoChronos, true);
                        } else {
                          final cmd = ChronosGuardService.getInstallCliCommand();
                          await Clipboard.setData(ClipboardData(text: cmd));
                          showSnack(tr.comandoCopiadoExecuteNoTerminalPara, true);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr.fechar),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent.shade700),
                icon: installing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.security_update_good, size: 16),
                label: Text(
                  installing
                      ? tr.configurando
                      : tr.instalarAtualizarEmTodosOsNavegadores,
                ),
                onPressed: installing
                    ? null
                    : () async {
                        setDialogState(() => installing = true);
                        try {
                          final ac = await getAntiCheatState();
                          if (!ctx.mounted) return;
                          await runUnifiedBrowserSetupFlow(
                            ctx,
                            isAntiCheatActive: ac.isActive,
                            onRefresh: refreshDialog,
                            onFeedback: showSnack,
                            onPolkitFallback: () async {
                              final launched = await ChronosGuardService.launchInstallerInTerminal();
                              if (!launched) {
                                final cmd = ChronosGuardService.getInstallCliCommand();
                                await Clipboard.setData(ClipboardData(text: cmd));
                                showSnack(tr.comandoGuardCopiadoParaOTerminal, false);
                              }
                            },
                          );
                        } finally {
                          if (ctx.mounted) setDialogState(() => installing = false);
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          tabs: [
            Tab(
              icon: const Icon(Icons.lock_clock),
              text: tr.sessoesBloqueiosP0(_rules.length),
            ),
            Tab(
              icon: const Icon(Icons.verified_user),
              text: tr.listaBrancaWhitelistP0(_whitelistGroups.length),
            ),
          ],
        ),
        _buildConflictsBanner(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRulesList(),
              _buildWhitelistList(),
            ],
          ),
        ),
      ],
    );
  }

  /// Existing conflicts (whitelist x block, two whitelists, overlapping blocks, YouTube
  /// "show only"). New ones are refused on save; these were there before.
  Widget _buildConflictsBanner() {
    List<ConflictDto> conflicts;
    try {
      conflicts = getConflicts();
    } catch (_) {
      conflicts = const [];
    }
    if (conflicts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(tr.conflitosEncontradosP0(conflicts.length),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
            ],
          ),
          const SizedBox(height: 4),
          for (final c in conflicts.take(6))
            Text('• ${c.message}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (conflicts.length > 6)
            Text(tr.eMaisP0(conflicts.length - 6), style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildRulesList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              final buttons = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.extension, size: 16, color: Colors.blueAccent),
                    label: Text(tr.extensaoWeb, style: TextStyle(color: Colors.blueAccent)),
                    onPressed: _showExtensionDialog,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr.novaSessaoDeBloqueio),
                    onPressed: _openAddRuleDialog,
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.sessoesConfiguradasP0(_rules.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    buttons,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      tr.sessoesConfiguradasP0(_rules.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  buttons,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: _rules.isEmpty
              ? Center(
                  child: Text(
                    tr.nenhumaSessaoCriadaAindaCliqueEm,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    final isSelected = rule.entityId == widget.activeEntityId;
                    final isExpanded = _expandedRuleIds.contains(rule.entityId);
                    final isRatchetActive = rule.ratchetLockedUntilUtc != null &&
                        rule.ratchetLockedUntilUtc! >
                            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
                    final typeColor = _getColorForType(rule.targetType);
                    final (appsList, sitesList) = _parseRuleAppsAndSites(rule);
                    final twBadge = _extractTimeWindowBadge(rule.scheduleJson);

                    return Card(
                      elevation: isSelected ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected ? Colors.tealAccent : Colors.white12,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      color: isSelected ? Colors.teal.shade900.withValues(alpha: 0.25) : Colors.grey.shade900,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedRuleIds.remove(rule.entityId);
                                        } else {
                                          _expandedRuleIds.add(rule.entityId);
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: rule.isBlockedCompletely
                                              ? Colors.red.shade900
                                              : (isSelected ? Colors.teal.shade800 : Colors.grey.shade800),
                                          child: Icon(
                                            rule.isBlockedCompletely ? Icons.block : _getIconForType(rule.targetType),
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    rule.displayName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: typeColor.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: typeColor, width: 0.8),
                                                    ),
                                                    child: Text(
                                                      rule.targetType,
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor),
                                                    ),
                                                  ),
                                                  if (twBadge != null)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: Colors.orangeAccent, width: 0.8),
                                                      ),
                                                      child: Text(
                                                        twBadge,
                                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                                                      ),
                                                    ),
                                                  if (isSelected)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.teal.shade700,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text('MONITORANDO',
                                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _ruleQuotaSummary(rule),
                                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                              ),
                                              if (isRatchetActive)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.lock_clock, size: 14, color: Colors.amber.shade300),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        tr.catracaTravadaAumentosProibidos,
                                                        style: TextStyle(fontSize: 11, color: Colors.amber.shade300),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                LayoutBuilder(
                                    builder: (context, constraints) {
                                      final screenWidth = MediaQuery.of(context).size.width;
                                      final isCompact = screenWidth < 800;

                                      if (isCompact) {
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: isExpanded ? tr.recolher : tr.expandir,
                                              icon: Icon(
                                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                                color: Colors.tealAccent,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  if (isExpanded) {
                                                    _expandedRuleIds.remove(rule.entityId);
                                                  } else {
                                                    _expandedRuleIds.add(rule.entityId);
                                                  }
                                                });
                                              },
                                            ),
                                            IconButton(
                                              tooltip: tr.editarTempoDeBloqueio,
                                              icon: const Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 20),
                                              onPressed: () => _editRuleTime(rule),
                                            ),
                                            IconButton(
                                              tooltip: tr.adicionarAppsSitesAoGrupo,
                                              icon: const Icon(Icons.library_add_outlined, color: Colors.cyanAccent, size: 20),
                                              onPressed: () => _addAppsToRule(rule),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                                              onSelected: (val) {
                                                if (val == 'rename') {
                                                  _renameRule(rule);
                                                } else if (val == 'time') {
                                                  _editRuleTime(rule);
                                                } else if (val == 'apps') {
                                                  _addAppsToRule(rule);
                                                } else if (val == 'select') {
                                                  widget.onSelectEntity(rule.entityId);
                                                } else if (val == 'block') {
                                                  _toggleBlock(rule.entityId, rule.isBlockedCompletely);
                                                } else if (val == 'delete') {
                                                  _deleteRule(rule.entityId);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                PopupMenuItem(
                                                  value: 'rename',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.drive_file_rename_outline, color: Colors.white70, size: 16),
                                                      SizedBox(width: 8),
                                                      Text(tr.renomear),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'time',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text(tr.editarTempoDeBloqueio),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'apps',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.library_add_outlined, color: Colors.cyanAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text(tr.adicionarAppsSitesAoGrupo),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'select',
                                                  child: Row(
                                                    children: [
                                                      Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Colors.tealAccent, size: 16),
                                                      const SizedBox(width: 8),
                                                      Text(tr.focarNoDashboard),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'block',
                                                  child: Row(
                                                    children: [
                                                      Icon(rule.isBlockedCompletely ? Icons.lock_open : Icons.lock, color: rule.isBlockedCompletely ? Colors.greenAccent : Colors.redAccent, size: 16),
                                                      const SizedBox(width: 8),
                                                      Text(rule.isBlockedCompletely ? tr.desbloquear : tr.bloquearCompletamente),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text(tr.removerSessao),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: isExpanded ? tr.recolherItensDaSessao : tr.expandirParaVerTodosOsApps,
                                            icon: Icon(
                                              isExpanded ? Icons.expand_less : Icons.expand_more,
                                              color: Colors.tealAccent,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                if (isExpanded) {
                                                  _expandedRuleIds.remove(rule.entityId);
                                                } else {
                                                  _expandedRuleIds.add(rule.entityId);
                                                }
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip: tr.editarTempoDeBloqueio,
                                            icon: const Icon(Icons.timer_outlined, color: Colors.amberAccent),
                                            onPressed: () => _editRuleTime(rule),
                                          ),
                                          IconButton(
                                            tooltip: tr.adicionarAplicativosSitesPermitidoNoAnti,
                                            icon: const Icon(Icons.library_add_outlined, color: Colors.cyanAccent),
                                            onPressed: () => _addAppsToRule(rule),
                                          ),
                                          IconButton(
                                            tooltip: isSelected ? tr.sessaoSelecionada : tr.focarNoDashboard,
                                            icon: Icon(
                                              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                              color: isSelected ? Colors.tealAccent : Colors.grey,
                                            ),
                                            onPressed: () => widget.onSelectEntity(rule.entityId),
                                          ),
                                          IconButton(
                                            tooltip: rule.isBlockedCompletely ? tr.desbloquear : tr.bloquearCompletamente,
                                            icon: Icon(
                                              rule.isBlockedCompletely ? Icons.lock : Icons.lock_open,
                                              color: rule.isBlockedCompletely ? Colors.redAccent : Colors.greenAccent,
                                            ),
                                            onPressed: () => _toggleBlock(rule.entityId, rule.isBlockedCompletely),
                                          ),
                                          IconButton(
                                            tooltip: tr.removerSessao,
                                            icon: const Icon(Icons.delete_outline, color: Colors.white38),
                                            onPressed: () => _deleteRule(rule.entityId),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 10),
                                const Divider(color: Colors.white12, height: 1),
                                const SizedBox(height: 10),
                                if (appsList.isNotEmpty) ...[
                                  Text(
                                    tr.aplicativosBloqueadosP0(appsList.length),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purpleAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: appsList.map((appItem) {
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade900.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.apps, size: 16, color: Colors.purpleAccent),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                appItem.name,
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: tr.removerP0DoGrupoAntiCheat(appItem.name),
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                              onPressed: () => _removeAppFromRule(rule, appItem.raw, appItem.name),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (sitesList.isNotEmpty) ...[
                                  Text(
                                    tr.sitesEPalavrasChaveBloqueadosP0(sitesList.length),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.lightBlueAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: sitesList.map((site) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.public, size: 13, color: Colors.lightBlueAccent),
                                            const SizedBox(width: 5),
                                            Text(site, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (appsList.isEmpty && sitesList.isEmpty)
                                  Text(
                                    tr.nenhumAplicativoOuSiteListadoNesta,
                                    style: TextStyle(fontSize: 12, color: Colors.white54),
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
    );
  }

  Widget _buildWhitelistList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr.gruposDeListaBrancaP0(_whitelistGroups.length),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
                icon: const Icon(Icons.verified_user, size: 18),
                label: Text(tr.novoGrupoDeListaBranca),
                onPressed: _openAddWhitelistDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _whitelistGroups.isEmpty
              ? Center(
                  child: Text(
                    tr.nenhumGrupoDeListaBrancaCriado,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _whitelistGroups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final group = _whitelistGroups[index];
                    final isExpanded = _expandedWhitelistIds.contains(group.groupId);
                    final (appsList, sitesList) = _parseWhitelistAppsAndSites(group);

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.teal, width: 1),
                      ),
                      color: Colors.teal.shade900.withValues(alpha: 0.15),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedWhitelistIds.remove(group.groupId);
                                        } else {
                                          _expandedWhitelistIds.add(group.groupId);
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          backgroundColor: Colors.teal,
                                          child: Icon(Icons.shield, color: Colors.white, size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    group.displayName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal.withValues(alpha: 0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.tealAccent, width: 0.8),
                                                    ),
                                                    child: Text(
                                                      tr.protecaoTotal,
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                                                    ),
                                                  ),
                                                  if (appsList.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.purple.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '${appsList.length} apps',
                                                        style: const TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  if (sitesList.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '${sitesList.length} sites',
                                                        style: const TextStyle(fontSize: 10, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  if (_whitelistYoutubeTypeCount(group) > 0)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        tr.p0TiposYoutube(_whitelistYoutubeTypeCount(group)),
                                                        style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                tr.itensProtegidosContraContagemDeTempo,
                                                style: TextStyle(color: Colors.white60, fontSize: 12),
                                              ),
                                              if (_whitelistYoutubeTypeLabels(group).isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    tr.youtubePermitidoP0(_whitelistYoutubeTypeLabels(group).join(', ')),
                                                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final screenWidth = MediaQuery.of(context).size.width;
                                    final isCompact = screenWidth < 800;

                                    if (isCompact) {
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            tooltip: isExpanded ? tr.recolherItens : tr.expandirItens,
                                            icon: Icon(
                                              isExpanded ? Icons.expand_less : Icons.expand_more,
                                              color: Colors.tealAccent,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                if (isExpanded) {
                                                  _expandedWhitelistIds.remove(group.groupId);
                                                } else {
                                                  _expandedWhitelistIds.add(group.groupId);
                                                }
                                              });
                                            },
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            tooltip: tr.editarGrupo,
                                            icon: const Icon(Icons.edit_outlined, color: Colors.cyanAccent, size: 20),
                                            onPressed: () => _openAddWhitelistDialog(group),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            tooltip: tr.removerGrupo,
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                            onPressed: () => _deleteWhitelist(group.groupId),
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          tooltip: isExpanded ? tr.recolherItens : tr.expandirItens,
                                          icon: Icon(
                                            isExpanded ? Icons.expand_less : Icons.expand_more,
                                            color: Colors.tealAccent,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              if (isExpanded) {
                                                _expandedWhitelistIds.remove(group.groupId);
                                              } else {
                                                _expandedWhitelistIds.add(group.groupId);
                                              }
                                            });
                                          },
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          tooltip: tr.editarGrupoDeListaBranca,
                                          icon: const Icon(Icons.edit_outlined, color: Colors.cyanAccent),
                                          onPressed: () => _openAddWhitelistDialog(group),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          tooltip: tr.removerGrupoDeListaBranca,
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () => _deleteWhitelist(group.groupId),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 10),
                                const Divider(color: Colors.white12, height: 1),
                                const SizedBox(height: 10),
                                if (appsList.isNotEmpty) ...[
                                  Text(
                                    tr.aplicativosProtegidosP0(appsList.length),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                                  ),
                                  const SizedBox(height: 6),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: appsList.map((appItem) {
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade900.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.shield, size: 16, color: Colors.tealAccent),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                appItem.name,
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: tr.removerP0DaListaBranca(appItem.name),
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                              onPressed: () => _removeAppFromWhitelist(group, appItem.raw, appItem.name),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (sitesList.isNotEmpty) ...[
                                  Text(
                                    tr.sitesEPalavrasProtegidosP0(sitesList.length),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: sitesList.map((site) {
                                      return Chip(
                                        backgroundColor: Colors.blue.shade900.withValues(alpha: 0.4),
                                        avatar: const Icon(Icons.public, size: 14, color: Colors.lightBlueAccent),
                                        label: Text(site, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (_whitelistYoutubeTypeLabels(group).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    tr.tiposDoYoutubePermitidosP0(_whitelistYoutubeTypeLabels(group).length),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _whitelistYoutubeTypeLabels(group).map((label) {
                                      return Chip(
                                        backgroundColor: Colors.red.shade900.withValues(alpha: 0.35),
                                        avatar: const Icon(Icons.play_circle_outline, size: 14, color: Colors.redAccent),
                                        label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                ),
        ),
      ],
    );
  }
}
