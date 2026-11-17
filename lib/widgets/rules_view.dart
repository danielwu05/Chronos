import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:chronos_app/services/web_block_server.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
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
              const Text('Modo Anti-Cheat Ativo!'),
            ],
          ),
          content: Text(
            state.mode == 'NUKE'
                ? 'O Chronos está no Modo Nuke (restam ${state.nukeRemainingSeconds ~/ 60}m). '
                  'Não é permitido $actionName até que o cronômetro expire.'
                : 'Não é permitido $actionName enquanto o Anti-Cheat estiver ativo. '
                  'Para alterar regras, você deve primeiro resolver o desafio de digitação estrito do Anti-Cheat.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
            if (state.mode == 'CHALLENGE')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
                icon: const Icon(Icons.lock_open, size: 16),
                label: const Text('Resolver Desafio'),
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
      final allowed = await _ensureAntiCheatAllowed('desbloquear entidades');
      if (!allowed) return;
    }
    final res = await toggleEntityBlock(entityId: entityId, blocked: !current);
    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _deleteRule(String entityId) async {
    final allowed = await _ensureAntiCheatAllowed('remover regras de bloqueio');
    if (!allowed) return;
    final res = await deleteRule(entityId: entityId);
    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _editRuleTime(RuleItemDto rule) async {
    final allowed = await _ensureAntiCheatAllowed('editar tempo de bloqueio e agendamento');
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

    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _addAppsToRule(RuleItemDto rule) async {
    // Adicionar aplicativos ou sites a uma sessão torna a regra mais restritiva,
    // portanto é 100% PERMITIDO mesmo com o Modo Anti-Cheat (inclusive Nuke) ativo!
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

    _showFeedback(res);
    await _loadAll();
    widget.onRulesUpdated();
  }

  Future<void> _openAddWhitelistDialog([WhitelistGroupDto? initial]) async {
    final allowed = await _ensureAntiCheatAllowed(
      initial != null ? 'editar grupos de lista branca' : 'adicionar grupos de lista branca',
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
        title: const Text('Remover Grupo de Lista Branca'),
        content: const Text(
          'Deseja realmente remover este grupo de lista branca? Os aplicativos e sites configurados nele deixarão de ser protegidos e voltarão a ser contabilizados ou bloqueados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
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
    final allowed = await _ensureAntiCheatAllowed('remover aplicativo do grupo de bloqueio');
    if (!allowed) return;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover do Grupo de Bloqueio'),
        content: Text('Deseja realmente remover "$appDisplayName" deste grupo de bloqueio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
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
          SnackBar(content: Text('Erro ao remover aplicativo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _removeAppFromWhitelist(WhitelistGroupDto group, dynamic rawAppItem, String appDisplayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da Lista Branca'),
        content: Text('Deseja remover "$appDisplayName" desta lista branca? O app deixará de ser protegido contra bloqueios.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
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
          SnackBar(content: Text('Erro ao remover da lista branca: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _formatSeconds(int s) {
    if (s <= 0) return '0m (Bloqueio Total)';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
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
          if (apps.isNotEmpty) parts.add('${apps.length} aplicativo(s)');
          if (sites.isNotEmpty) parts.add('${sites.length} site(s)/palavra(s)');
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
        final mode = map['time_window_mode'] == 'ALLOW_INSIDE' ? 'Permitir somente' : 'Bloquear';
        return 'Janela: $mode $start-$end';
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
            title: const Row(
              children: [
                Icon(Icons.extension, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('Extensão & Proteção dos Navegadores'),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'O Chronos aplica a extensão em navegadores Chromium e o Proxy Seletivo + CA no Firefox de forma totalmente offline.',
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
                      'Navegadores instalados detectados (${browsers.length}):',
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
                          'Servidor local ativo na porta ${WebBlockServer.port}',
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
                          'Chrome aberto em chrome://extensions! Cole o caminho copiado ao carregar sem compactação.',
                          true,
                        );
                      },
                      onShowFirefoxGuide: () async {
                        await BrowserExtensionInstaller.launchFirefoxWithExtensionGuide();
                        showSnack(
                          'Firefox aberto em about:policies para inspeção das políticas locais.',
                          true,
                        );
                      },
                      onShowGuardTerminal: () async {
                        final launched = await ChronosGuardService.launchInstallerInTerminal();
                        if (launched) {
                          showSnack('Terminal aberto para autorização do Chronos Guard!', true);
                        } else {
                          final cmd = ChronosGuardService.getInstallCliCommand();
                          await Clipboard.setData(ClipboardData(text: cmd));
                          showSnack('Comando copiado! Execute no terminal para instalar o Guard.', true);
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
                child: const Text('Fechar'),
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
                      ? 'Configurando...'
                      : 'Instalar / Atualizar em Todos os Navegadores',
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
                                showSnack('Comando Guard copiado para o terminal!', false);
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
              text: 'Sessões & Bloqueios (${_rules.length})',
            ),
            Tab(
              icon: const Icon(Icons.verified_user),
              text: 'Lista Branca / Whitelist (${_whitelistGroups.length})',
            ),
          ],
        ),
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
                    label: const Text('Extensão Web', style: TextStyle(color: Colors.blueAccent)),
                    onPressed: _showExtensionDialog,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nova Sessão de Bloqueio'),
                    onPressed: _openAddRuleDialog,
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sessões Configuradas (${_rules.length})',
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
                      'Sessões Configuradas (${_rules.length})',
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
              ? const Center(
                  child: Text(
                    'Nenhuma sessão criada ainda.\nClique em "Nova Sessão de Bloqueio" para agrupar apps ou sites.',
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
                                                rule.weekendQuotaSeconds != null && rule.weekendQuotaSeconds! > 0
                                                    ? 'Tempo de tela: ${_formatSeconds(rule.dailyQuotaSeconds)} (Fins de semana: ${_formatSeconds(rule.weekendQuotaSeconds!)}) • ${_formatPatternSummary(rule.pattern, rule.entityId)}'
                                                    : 'Tempo de tela: ${_formatSeconds(rule.dailyQuotaSeconds)} • ${_formatPatternSummary(rule.pattern, rule.entityId)}',
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
                                                        'Catraca Travada (Aumentos proibidos)',
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
                                              tooltip: isExpanded ? 'Recolher' : 'Expandir',
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
                                              tooltip: 'Editar Tempo de Bloqueio',
                                              icon: const Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 20),
                                              onPressed: () => _editRuleTime(rule),
                                            ),
                                            IconButton(
                                              tooltip: 'Adicionar Apps / Sites ao Grupo (Permitido com Anti-Cheat)',
                                              icon: const Icon(Icons.library_add_outlined, color: Colors.cyanAccent, size: 20),
                                              onPressed: () => _addAppsToRule(rule),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                                              onSelected: (val) {
                                                if (val == 'time') {
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
                                                const PopupMenuItem(
                                                  value: 'time',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text('Editar Tempo de Bloqueio'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'apps',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.library_add_outlined, color: Colors.cyanAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text('Adicionar Apps / Sites ao Grupo'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'select',
                                                  child: Row(
                                                    children: [
                                                      Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Colors.tealAccent, size: 16),
                                                      const SizedBox(width: 8),
                                                      const Text('Focar no Dashboard'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'block',
                                                  child: Row(
                                                    children: [
                                                      Icon(rule.isBlockedCompletely ? Icons.lock_open : Icons.lock, color: rule.isBlockedCompletely ? Colors.greenAccent : Colors.redAccent, size: 16),
                                                      const SizedBox(width: 8),
                                                      Text(rule.isBlockedCompletely ? 'Desbloquear' : 'Bloquear Completamente'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                                      SizedBox(width: 8),
                                                      Text('Remover Sessão'),
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
                                            tooltip: isExpanded ? 'Recolher itens da sessão' : 'Expandir para ver todos os apps e sites',
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
                                            tooltip: 'Editar Tempo de Bloqueio',
                                            icon: const Icon(Icons.timer_outlined, color: Colors.amberAccent),
                                            onPressed: () => _editRuleTime(rule),
                                          ),
                                          IconButton(
                                            tooltip: 'Adicionar Aplicativos / Sites (Permitido no Anti-Cheat)',
                                            icon: const Icon(Icons.library_add_outlined, color: Colors.cyanAccent),
                                            onPressed: () => _addAppsToRule(rule),
                                          ),
                                          IconButton(
                                            tooltip: isSelected ? 'Sessão selecionada' : 'Focar no Dashboard',
                                            icon: Icon(
                                              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                              color: isSelected ? Colors.tealAccent : Colors.grey,
                                            ),
                                            onPressed: () => widget.onSelectEntity(rule.entityId),
                                          ),
                                          IconButton(
                                            tooltip: rule.isBlockedCompletely ? 'Desbloquear' : 'Bloquear Completamente',
                                            icon: Icon(
                                              rule.isBlockedCompletely ? Icons.lock : Icons.lock_open,
                                              color: rule.isBlockedCompletely ? Colors.redAccent : Colors.greenAccent,
                                            ),
                                            onPressed: () => _toggleBlock(rule.entityId, rule.isBlockedCompletely),
                                          ),
                                          IconButton(
                                            tooltip: 'Remover Sessão',
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
                                    'Aplicativos Bloqueados (${appsList.length}):',
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
                                              tooltip: 'Remover ${appItem.name} do grupo (Anti-Cheat restrito)',
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
                                    'Sites e Palavras-Chave Bloqueados (${sitesList.length}):',
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
                                  const Text(
                                    'Nenhum aplicativo ou site listado nesta sessão.',
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
                'Grupos de Lista Branca (${_whitelistGroups.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
                icon: const Icon(Icons.verified_user, size: 18),
                label: const Text('Novo Grupo de Lista Branca'),
                onPressed: _openAddWhitelistDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _whitelistGroups.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum grupo de lista branca criado.\nApps e sites em listas brancas são protegidos contra bloqueios e finalizações.',
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
                                                    child: const Text(
                                                      'PROTEÇÃO TOTAL',
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
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                'Itens protegidos contra contagem de tempo de tela e fechamento automático',
                                                style: TextStyle(color: Colors.white60, fontSize: 12),
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
                                            tooltip: isExpanded ? 'Recolher itens' : 'Expandir itens',
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
                                            tooltip: 'Editar Grupo',
                                            icon: const Icon(Icons.edit_outlined, color: Colors.cyanAccent, size: 20),
                                            onPressed: () => _openAddWhitelistDialog(group),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            tooltip: 'Remover Grupo',
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
                                          tooltip: isExpanded ? 'Recolher itens' : 'Expandir itens',
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
                                          tooltip: 'Editar Grupo de Lista Branca',
                                          icon: const Icon(Icons.edit_outlined, color: Colors.cyanAccent),
                                          onPressed: () => _openAddWhitelistDialog(group),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          tooltip: 'Remover Grupo de Lista Branca',
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
                                    'Aplicativos Protegidos (${appsList.length}):',
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
                                              tooltip: 'Remover ${appItem.name} da lista branca',
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
                                    'Sites e Palavras Protegidos (${sitesList.length}):',
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
