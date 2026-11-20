import 'package:chronos_app/services/app_locale.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/src/rust/api/youtube.dart';
import 'package:chronos_app/src/rust/api/holidays.dart';

class BlockConfigResult {
  final String entityId;
  final String displayName;
  final int dailyQuotaSeconds;
  final String mode;
  final String targetType; // 'GROUP'
  final String pattern; // JSON string {"apps": [...], "sites": [...]}
  final bool isCompletelyBlocked;
  final int? weekendQuotaSeconds;
  /// Holiday quota (holiday > weekend > weekday); null = use the normal/weekend quota.
  final int? holidayQuotaSeconds;
  final String? scheduleJson;

  BlockConfigResult({
    required this.entityId,
    required this.displayName,
    required this.dailyQuotaSeconds,
    required this.mode,
    required this.targetType,
    required this.pattern,
    required this.isCompletelyBlocked,
    this.weekendQuotaSeconds,
    this.holidayQuotaSeconds,
    this.scheduleJson,
  });
}

enum BlockDialogMode {
  full,
  timeOnly,
  appsOnly,
}

class AddBlockDialog extends StatefulWidget {
  final String defaultMode;
  final RuleItemDto? initialRule;
  final bool isWhitelist;
  final WhitelistGroupDto? initialWhitelistGroup;
  final BlockDialogMode dialogMode;
  final Future<List<InstalledAppDto>> Function()? installedAppsLoader;

  const AddBlockDialog({
    super.key,
    this.defaultMode = 'SELF_CONTROL',
    this.initialRule,
    this.isWhitelist = false,
    this.initialWhitelistGroup,
    this.dialogMode = BlockDialogMode.full,
    this.installedAppsLoader,
  });

  static Future<BlockConfigResult?> show(
    BuildContext context, {
    String defaultMode = 'SELF_CONTROL',
    RuleItemDto? initialRule,
    bool isWhitelist = false,
    WhitelistGroupDto? initialWhitelistGroup,
    BlockDialogMode dialogMode = BlockDialogMode.full,
  }) {
    return showDialog<BlockConfigResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AddBlockDialog(
        defaultMode: defaultMode,
        initialRule: initialRule,
        isWhitelist: isWhitelist,
        initialWhitelistGroup: initialWhitelistGroup,
        dialogMode: dialogMode,
      ),
    );
  }

  @override
  State<AddBlockDialog> createState() => _AddBlockDialogState();
}

class _SavedAppRef {
  final String name;
  final String exec;
  const _SavedAppRef({required this.name, required this.exec});
}

class _AddBlockDialogState extends State<AddBlockDialog> {
  static List<InstalledAppDto>? _globalInstalledAppsCache;

  // 0: Composição do Grupo Unificado (Apps & Sites)
  // 1: Tempo de Tela & Salvar (com Relógio Digital, Janela de Horário e Notificações)
  int _step = 0;
  int _groupSubTab = 0; // 0: Apps, 1: Sites

  // Dados do Aplicativo Instalado
  List<InstalledAppDto> _installedApps = [];
  bool _loadingApps = false;
  final List<_SavedAppRef> _pendingAppEntries = [];

  // Dados do Bloqueio Escolhido
  String _selectedId = '';
  String _selectedName = '';
  String _selectedPattern = '';
  String _targetType = 'GROUP';

  // Configuração de Sessão Unificada
  final TextEditingController _groupNameController = TextEditingController(text: '');
  final TextEditingController _groupSearchController = TextEditingController();
  final Set<String> _selectedAppKeys = {};
  final Map<String, InstalledAppDto> _selectedAppObjects = {};
  final Set<String> _lockedAppIdentities = {};
  List<InstalledAppDto> _filteredGroupApps = [];
  // Category tags are data (Portuguese names from the Rust engine); only the chip label
  // is translated (_tagLabel).
  String _selectedTagFilter = 'Todas';
  Map<String, List<String>> _customAppTags = {}; // exec -> [tags]

  // Configuração de Sites e Palavras
  final TextEditingController _siteInputController = TextEditingController();
  final List<String> _siteGroupItems = [];
  final Set<String> _lockedSiteItems = {};
  final List<String> _keywordGroupItems = [];
  String? _duplicateSiteNotice;

  // Tipos de vídeo do YouTube isentos (só na Lista Branca): tipo -> teto diário em minutos (null = sem teto)
  final Map<String, int?> _ytTypes = {};

  // Tempo de Tela Diário e Final de Semana (Padrão 1:00 = 60 minutos)
  int _quotaMinutes = 60;
  bool _isCompletelyBlocked = false;
  bool _customWeekendQuota = false;
  int _weekendQuotaMinutes = 180;
  bool _customHolidayQuota = false;
  int _holidayQuotaMinutes = 240;

  // Seleção de Dias e Presets
  String _daysPreset = 'ALL'; // 'ALL', 'WEEKDAYS', 'WEEKENDS', 'CUSTOM'
  final Set<int> _selectedDays = {1, 2, 3, 4, 5, 6, 7}; // 1 = Seg, 7 = Dom

  // Janela de Horário (Time Window)
  bool _timeWindowEnabled = false;
  TimeOfDay _timeWindowStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _timeWindowEnd = const TimeOfDay(hour: 18, minute: 0);
  String _timeWindowMode = 'BLOCK_INSIDE'; // 'BLOCK_INSIDE' ou 'ALLOW_INSIDE'

  // Configuração de Notificações
  bool _notifyEnabled = true;
  bool _notifyRemaining = true;
  bool _notifyPeriodic = true;
  String _notifyMode = 'both'; // 'remaining', 'periodic', 'both', 'none'
  int _notifyIntervalMins = 15; // Intervalo periódico padrão
  final Set<int> _notifyRemainingThresholds = {15, 5, 1};

  static String _normalizeSiteToken(String raw) {
    var val = raw.trim().toLowerCase();
    if (val.isEmpty) return '';
    val = val
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('www.', '')
        .replaceAll(RegExp(r'/+$'), '');
    return val.trim();
  }

  static String _canonicalAppIdentity(String name, String exec) {
    final normExec = exec.trim().toLowerCase();
    final normName = name.trim().toLowerCase();
    return '${normName.isEmpty ? normExec : normName}___$normExec';
  }

  void _hydrateGroupItemsFromRaw(
    String raw, {
    required String fallbackTargetType,
    required bool lockExisting,
  }) {
    void addSite(String candidate) {
      final norm = _normalizeSiteToken(candidate);
      if (norm.isEmpty) return;
      if (!_siteGroupItems.contains(norm)) {
        _siteGroupItems.add(norm);
      }
      if (lockExisting) {
        _lockedSiteItems.add(norm);
      }
    }

    void addApp(String rawName, String rawExec) {
      final exec = rawExec.trim();
      final name = rawName.trim().isEmpty ? exec : rawName.trim();
      if (exec.isEmpty && name.isEmpty) return;
      final resolvedExec = exec.isEmpty ? name : exec;
      final identity = _canonicalAppIdentity(name, resolvedExec);
      final alreadyPending = _pendingAppEntries.any(
        (e) => _canonicalAppIdentity(e.name, e.exec) == identity,
      );
      if (!alreadyPending) {
        _pendingAppEntries.add(_SavedAppRef(name: name, exec: resolvedExec));
      }
      if (lockExisting) {
        _lockedAppIdentities.add(identity);
      }
    }

    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          if (decoded['sites'] is List) {
            for (final s in decoded['sites']) {
              if (s is String) addSite(s);
            }
          }
          if (decoded['keywords'] is List) {
            for (final k in decoded['keywords']) {
              if (k is String) {
                final kw = k.trim();
                if (kw.isNotEmpty && !_keywordGroupItems.contains(kw)) {
                  _keywordGroupItems.add(kw);
                }
              }
            }
          }
          if (decoded['apps'] is List) {
            for (final a in decoded['apps']) {
              if (a is String && a.trim().isNotEmpty) {
                addApp(a.trim(), a.trim());
              } else if (a is Map) {
                final ex = (a['exec'] ?? a['name'] ?? '').toString();
                final nm = (a['name'] ?? a['exec'] ?? '').toString();
                addApp(nm, ex);
              }
            }
          }
          if (decoded['yt_types'] is List) {
            for (final t in decoded['yt_types']) {
              if (t is String && t.trim().isNotEmpty) {
                _ytTypes[t.trim()] = null;
              } else if (t is Map && (t['type'] ?? '').toString().isNotEmpty) {
                final cap = t['cap_minutes'];
                _ytTypes[t['type'].toString()] = cap is int && cap > 0 ? cap : null;
              }
            }
          }
        }
      } catch (_) {}
    } else if (trimmed.isNotEmpty) {
      for (final p in trimmed.split(',')) {
        final t = p.trim();
        if (t.isEmpty) continue;
        final upper = fallbackTargetType.toUpperCase();
        if (upper == 'SITE' || upper == 'KEYWORD' || upper == 'SITE_GROUP' ||
            (t.contains('.') && !t.endsWith('.exe'))) {
          addSite(t);
        } else {
          addApp(t, t);
        }
      }
    }

    // Semeia imediatamente objetos sintéticos para nunca perder apps já salvos
    // caso o usuário clique em Salvar antes do término do carregamento assíncrono.
    for (final entry in _pendingAppEntries) {
      final synthetic = InstalledAppDto(
        id: 'saved___${_canonicalAppIdentity(entry.name, entry.exec)}',
        name: entry.name,
        exec: entry.exec,
        iconName: '',
        iconPath: '',
      );
      final key = _appUniqueKey(synthetic);
      _selectedAppKeys.add(key);
      _selectedAppObjects[key] = synthetic;
    }
  }

  @override
  void initState() {
    super.initState();
    _step = widget.dialogMode == BlockDialogMode.timeOnly ? 1 : 0;
    _groupSearchController.addListener(_onGroupSearchChanged);
    final lockExisting = widget.dialogMode == BlockDialogMode.appsOnly;
    _loadInstalledApps();

    if (widget.initialWhitelistGroup != null) {
      final wl = widget.initialWhitelistGroup!;
      _selectedId = wl.groupId;
      _selectedName = wl.displayName;
      _groupNameController.text = wl.displayName;
      _hydrateGroupItemsFromRaw(
        wl.items,
        fallbackTargetType: 'GROUP',
        lockExisting: lockExisting,
      );
    } else if (widget.initialRule != null) {
      final r = widget.initialRule!;
      _selectedId = r.entityId;
      _selectedName = r.displayName;
      _groupNameController.text = r.displayName;
      _selectedPattern = r.pattern;
      _targetType = 'GROUP';
      _quotaMinutes = (r.dailyQuotaSeconds ~/ 60).clamp(0, 1440);
      _isCompletelyBlocked = r.isBlockedCompletely;

      _hydrateGroupItemsFromRaw(
        r.pattern,
        fallbackTargetType: r.targetType,
        lockExisting: lockExisting,
      );

      if (r.weekendQuotaSeconds != null && r.weekendQuotaSeconds! > 0) {
        _customWeekendQuota = true;
        _weekendQuotaMinutes = (r.weekendQuotaSeconds! ~/ 60).clamp(1, 1440);
      }
      try {
        for (final hq in getHolidayQuotas()) {
          if (hq.entityId == r.entityId && hq.seconds > 0) {
            _customHolidayQuota = true;
            _holidayQuotaMinutes = (hq.seconds.toInt() ~/ 60).clamp(15, 720);
          }
        }
      } catch (_) {}

      if (r.scheduleJson != null && r.scheduleJson!.isNotEmpty) {
        try {
          final map = jsonDecode(r.scheduleJson!);
          if (map['preset'] is String) _daysPreset = map['preset'];
          if (map['days'] is List) {
            _selectedDays.clear();
            for (final d in map['days']) {
              if (d is int) _selectedDays.add(d);
            }
          }
          if (map['time_window_enabled'] == true) {
            _timeWindowEnabled = true;
            if (map['time_window_start'] is String) {
              final parts = (map['time_window_start'] as String).split(':');
              if (parts.length >= 2) {
                _timeWindowStart = TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
              }
            }
            if (map['time_window_end'] is String) {
              final parts = (map['time_window_end'] as String).split(':');
              if (parts.length >= 2) {
                _timeWindowEnd = TimeOfDay(hour: int.tryParse(parts[0]) ?? 18, minute: int.tryParse(parts[1]) ?? 0);
              }
            }
            if (map['time_window_mode'] is String) {
              _timeWindowMode = map['time_window_mode'];
            }
          }
          if (map['notify_mode'] is String) {
            _notifyMode = map['notify_mode'];
            _notifyEnabled = _notifyMode != 'none';
            _notifyRemaining = _notifyMode == 'both' || _notifyMode == 'remaining';
            _notifyPeriodic = _notifyMode == 'both' || _notifyMode == 'periodic';
          }
          if (map['notify_interval_mins'] is num) {
            _notifyIntervalMins = (map['notify_interval_mins'] as num).toInt();
          }
        } catch (_) {}
      }
    } else {
      _quotaMinutes = 60; // 1:00 padrão
    }
  }

  @override
  void dispose() {
    _groupSearchController.dispose();
    _groupNameController.dispose();
    _siteInputController.dispose();
    super.dispose();
  }

  String _appUniqueKey(InstalledAppDto app) => '${app.id}___${app.name}___${app.exec}';

  File _getCustomTagsFile() {
    final home = Platform.environment['HOME'] ?? '/home/dwu';
    return File('$home/.config/chronos_custom_app_tags.json');
  }

  void _loadCustomTags() {
    try {
      final f = _getCustomTagsFile();
      if (f.existsSync()) {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map) {
          _customAppTags = decoded.map((k, v) => MapEntry(
                k.toString(),
                (v is List) ? v.map((e) => e.toString()).toList() : <String>[],
              ));
        }
      }
    } catch (_) {}
  }

  void _saveCustomTags() {
    try {
      final f = _getCustomTagsFile();
      f.writeAsStringSync(jsonEncode(_customAppTags));
    } catch (_) {}
  }

  static const Set<String> _kAppCategories = {
    'Jogos', 'Navegadores', 'Comunicação', 'Internet', 'Mídia', 'Desenvolvimento',
    'Escritório', 'Gráficos', 'Educação', 'Sistema', 'Utilitários', 'Outros',
  };

  /// Display label of a category tag in the current language (custom tags as typed).
  static String _tagLabel(String tag) => switch (tag) {
        'Todas' => tr.todas,
        'Jogos' => tr.jogos,
        'Navegadores' => tr.navegadores,
        'Comunicação' => tr.comunicacao,
        'Internet' => tr.internet,
        'Mídia' => tr.midia,
        'Desenvolvimento' => tr.desenvolvimento,
        'Escritório' => tr.escritorio,
        'Gráficos' => tr.graficos,
        'Educação' => tr.educacao,
        'Sistema' => tr.sistema,
        'Utilitários' => tr.utilitarios,
        'Outros' => tr.outros,
        _ => tag,
      };

  List<String> _getAppTags(InstalledAppDto app) {
    final tags = <String>{};
    // Tags extraídas do arquivo .desktop (armazenadas em iconName pelo motor Rust)
    if (app.iconName.contains(',')) {
      for (final t in app.iconName.split(',')) {
        final clean = t.trim();
        if (clean.isNotEmpty) tags.add(clean);
      }
    } else if (app.iconName.trim().isNotEmpty &&
        _kAppCategories.contains(app.iconName.trim())) {
      tags.add(app.iconName.trim());
    }

    final custom = _customAppTags[app.exec.toLowerCase()] ?? const [];
    tags.addAll(custom);
    return tags.toList();
  }

  List<String> _getAllAvailableTags() {
    final tags = <String>{'Todas'};
    for (final app in _installedApps) {
      tags.addAll(_getAppTags(app));
    }
    for (final list in _customAppTags.values) {
      tags.addAll(list);
    }
    return tags.toList();
  }

  void _showAddCustomTagDialog(InstalledAppDto app) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.adicionarTagP0(app.name), style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr.nomeDaTagExRedesSociais,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            final clean = val.trim();
            if (clean.isNotEmpty) {
              setState(() {
                final list = _customAppTags.putIfAbsent(app.exec.toLowerCase(), () => []);
                if (!list.contains(clean)) list.add(clean);
                _saveCustomTags();
                _applyAppFilters();
              });
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr.cancelar),
          ),
          FilledButton(
            onPressed: () {
              final clean = ctrl.text.trim();
              if (clean.isNotEmpty) {
                setState(() {
                  final list = _customAppTags.putIfAbsent(app.exec.toLowerCase(), () => []);
                  if (!list.contains(clean)) list.add(clean);
                  _saveCustomTags();
                  _applyAppFilters();
                });
              }
              Navigator.pop(ctx);
            },
            child: Text(tr.adicionarTag),
          ),
        ],
      ),
    );
  }

  void _onGroupSearchChanged() {
    setState(() {
      _applyAppFilters();
    });
  }

  void _applyAppFilters() {
    final query = _groupSearchController.text.toLowerCase().trim();
    _filteredGroupApps = _installedApps.where((a) {
      final appTags = _getAppTags(a);
      if (_selectedTagFilter != 'Todas' && !appTags.contains(_selectedTagFilter)) {
        return false;
      }
      if (query.isEmpty) return true;
      final matchesNameOrExec =
          a.name.toLowerCase().contains(query) || a.exec.toLowerCase().contains(query);
      final matchesTag = appTags.any((t) => t.toLowerCase().contains(query));
      return matchesNameOrExec || matchesTag;
    }).toList();
  }

  Future<void> _loadInstalledApps() async {
    _loadCustomTags();

    void finishLoad([List<InstalledAppDto>? loaded]) {
      if (!mounted) return;
      setState(() {
        if (loaded != null) {
          _installedApps = List<InstalledAppDto>.from(loaded);
        }
        _matchPendingApps();
        _applyAppFilters();
        _loadingApps = false;
      });
    }

    if (widget.installedAppsLoader == null) {
      if (_installedApps.isNotEmpty) {
        finishLoad();
        return;
      }
      if (_globalInstalledAppsCache != null && _globalInstalledAppsCache!.isNotEmpty) {
        finishLoad(_globalInstalledAppsCache);
        return;
      }
    }

    if (mounted) {
      setState(() => _loadingApps = true);
    }
    try {
      final list = widget.installedAppsLoader != null
          ? await widget.installedAppsLoader!()
          : await getInstalledApplications().timeout(
              const Duration(seconds: 4),
              onTimeout: () => <InstalledAppDto>[],
            );
      if (widget.installedAppsLoader == null) {
        _globalInstalledAppsCache = list;
      }
      finishLoad(list);
    } catch (_) {
      finishLoad();
    }
  }

  bool _isAppLocked(InstalledAppDto app) {
    if (widget.dialogMode != BlockDialogMode.appsOnly) return false;
    final id = _canonicalAppIdentity(app.name, app.exec);
    if (_lockedAppIdentities.contains(id)) return true;
    // Fallback para registros legados salvos apenas como string de exec
    return _lockedAppIdentities.contains(_canonicalAppIdentity(app.exec, app.exec));
  }

  bool _isSiteLocked(String item) {
    if (widget.dialogMode != BlockDialogMode.appsOnly) return false;
    return _lockedSiteItems.contains(_normalizeSiteToken(item));
  }

  void _matchPendingApps() {
    if (_pendingAppEntries.isEmpty) return;
    final lockExisting = widget.dialogMode == BlockDialogMode.appsOnly;

    for (final entry in _pendingAppEntries) {
      final refIdentity = _canonicalAppIdentity(entry.name, entry.exec);
      final isLegacyExecOnly =
          entry.name.trim().toLowerCase() == entry.exec.trim().toLowerCase();

      InstalledAppDto? matched;
      for (final app in _installedApps) {
        if (app.exec.trim().toLowerCase() != entry.exec.trim().toLowerCase()) {
          continue;
        }
        if (app.name.trim().toLowerCase() == entry.name.trim().toLowerCase() ||
            isLegacyExecOnly) {
          matched = app;
          break;
        }
      }

      if (matched == null) {
        final synthetic = InstalledAppDto(
          id: 'saved___$refIdentity',
          name: entry.name,
          exec: entry.exec,
          iconName: '',
          iconPath: '',
        );
        final alreadyInList = _installedApps.any(
          (a) => _canonicalAppIdentity(a.name, a.exec) == refIdentity,
        );
        if (!alreadyInList) {
          _installedApps.insert(0, synthetic);
        }
        matched = synthetic;
      }

      final syntheticKey = _appUniqueKey(InstalledAppDto(
        id: 'saved___$refIdentity',
        name: entry.name,
        exec: entry.exec,
        iconName: '',
        iconPath: '',
      ));
      if (matched.id != 'saved___$refIdentity') {
        _selectedAppKeys.remove(syntheticKey);
        _selectedAppObjects.remove(syntheticKey);
      }

      final matchedKey = _appUniqueKey(matched);
      _selectedAppKeys.add(matchedKey);
      _selectedAppObjects[matchedKey] = matched;
      if (lockExisting) {
        _lockedAppIdentities.add(_canonicalAppIdentity(matched.name, matched.exec));
      }
    }
  }

  void _selectAllApps() {
    setState(() {
      for (final app in _filteredGroupApps) {
        final key = _appUniqueKey(app);
        _selectedAppKeys.add(key);
        _selectedAppObjects[key] = app;
      }
    });
  }

  void _deselectAllApps() {
    setState(() {
      final toRemove = <String>[];
      for (final key in _selectedAppKeys) {
        final obj = _selectedAppObjects[key];
        if (obj != null && _isAppLocked(obj)) continue;
        toRemove.add(key);
      }
      for (final key in toRemove) {
        _selectedAppKeys.remove(key);
        _selectedAppObjects.remove(key);
      }
    });
  }

  void _addSiteItem(String raw) {
    final val = _normalizeSiteToken(raw);
    if (val.isEmpty) return;
    if (_siteGroupItems.contains(val)) {
      setState(() {
        _duplicateSiteNotice = tr.p0JaFoiAdicionadoAoGrupo(val);
      });
      return;
    }
    setState(() {
      _duplicateSiteNotice = null;
      _siteGroupItems.add(val);
      _siteInputController.clear();
    });
  }

  List<Map<String, String>> _buildSerializedAppsPayload() {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final app in _selectedAppObjects.values) {
      final id = _canonicalAppIdentity(app.name, app.exec);
      if (seen.add(id)) {
        out.add({'name': app.name, 'exec': app.exec});
      }
    }
    return out;
  }

  String _buildGroupPatternJson() {
    final richApps = _buildSerializedAppsPayload();
    return jsonEncode({
      'apps': richApps,
      'sites': _siteGroupItems,
      if (_keywordGroupItems.isNotEmpty) 'keywords': _keywordGroupItems,
      if (widget.isWhitelist && _ytTypes.isNotEmpty)
        'yt_types': [
          for (final e in _ytTypes.entries)
            {'type': e.key, if (e.value != null && e.value! > 0) 'cap_minutes': e.value},
        ],
    });
  }

  void _onUnifiedGroupContinue() {
    if (_selectedAppKeys.isEmpty && _siteGroupItems.isEmpty && _keywordGroupItems.isEmpty) return;

    final name = _groupNameController.text.trim().isEmpty ? tr.sessaoDeFoco : _groupNameController.text.trim();
    final entityId = widget.initialRule?.entityId ??
        'group_${DateTime.now().millisecondsSinceEpoch}_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final patternJson = _buildGroupPatternJson();

    setState(() {
      _selectedId = entityId;
      _selectedName = name;
      _selectedPattern = patternJson;
      _targetType = 'GROUP';
      _step = 1;
    });
  }

  void _saveWhitelistDirectly() async {
    if (_selectedAppKeys.isEmpty && _siteGroupItems.isEmpty && _keywordGroupItems.isEmpty && _ytTypes.isEmpty) return;

    final name = _groupNameController.text.trim().isEmpty ? tr.listaBranca : _groupNameController.text.trim();
    final itemsJson = _buildGroupPatternJson();

    final gId = widget.initialWhitelistGroup?.groupId ??
        'wl_${DateTime.now().millisecondsSinceEpoch}';

    final res = await saveWhitelistGroup(
      groupId: gId,
      displayName: name,
      items: itemsJson,
    );

    if (mounted) {
      Navigator.pop(context, BlockConfigResult(
        entityId: gId,
        displayName: name,
        dailyQuotaSeconds: 0,
        mode: 'WHITELIST',
        targetType: 'GROUP',
        pattern: itemsJson,
        isCompletelyBlocked: false,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.success ? Colors.teal.shade700 : Colors.red.shade800,
        ),
      );
    }
  }

  void _saveAppsDirectly() {
    if (_selectedAppKeys.isEmpty && _siteGroupItems.isEmpty && _keywordGroupItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.selecionePeloMenosUmAplicativoOu)),
      );
      return;
    }

    final name = _groupNameController.text.trim().isEmpty
        ? (_selectedName.isEmpty ? tr.sessaoDeFoco : _selectedName)
        : _groupNameController.text.trim();

    final patternJson = _buildGroupPatternJson();

    final quotaSec = widget.initialRule != null
        ? widget.initialRule!.dailyQuotaSeconds
        : (_isCompletelyBlocked ? 0 : _quotaMinutes * 60);

    final result = BlockConfigResult(
      entityId: _selectedId,
      displayName: name,
      dailyQuotaSeconds: quotaSec,
      mode: widget.initialRule?.mode ?? widget.defaultMode,
      targetType: _targetType,
      pattern: patternJson,
      isCompletelyBlocked: widget.initialRule?.isBlockedCompletely ?? _isCompletelyBlocked,
      weekendQuotaSeconds: widget.initialRule?.weekendQuotaSeconds,
      scheduleJson: widget.initialRule?.scheduleJson,
    );

    Navigator.pop(context, result);
  }

  void _setPreset(String preset) {
    setState(() {
      _daysPreset = preset;
      switch (preset) {
        case 'ALL':
          _selectedDays.clear();
          _selectedDays.addAll({1, 2, 3, 4, 5, 6, 7});
          break;
        case 'WEEKDAYS':
          _selectedDays.clear();
          _selectedDays.addAll({1, 2, 3, 4, 5});
          break;
        case 'WEEKENDS':
          _selectedDays.clear();
          _selectedDays.addAll({6, 7});
          break;
        case 'CUSTOM':
          break;
      }
    });
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        if (_selectedDays.length > 1) {
          _selectedDays.remove(day);
          _daysPreset = 'CUSTOM';
        }
      } else {
        _selectedDays.add(day);
        if (_selectedDays.length == 7) {
          _daysPreset = 'ALL';
        } else if (_selectedDays.length == 5 &&
            _selectedDays.contains(1) &&
            _selectedDays.contains(2) &&
            _selectedDays.contains(3) &&
            _selectedDays.contains(4) &&
            _selectedDays.contains(5)) {
          _daysPreset = 'WEEKDAYS';
        } else if (_selectedDays.length == 2 && _selectedDays.contains(6) && _selectedDays.contains(7)) {
          _daysPreset = 'WEEKENDS';
        } else {
          _daysPreset = 'CUSTOM';
        }
      }
    });
  }

  String _formatDigitalTime(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatReadableTime(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m minutos';
    if (m == 0) return '$h horas';
    return tr.p0HP1Min(h, m);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _timeWindowStart : _timeWindowEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.tealAccent,
            onPrimary: Colors.black,
            surface: Color(0xFF1E232B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _timeWindowStart = picked;
        } else {
          _timeWindowEnd = picked;
        }
      });
    }
  }

  String? _todayHolidaySafe() {
    try {
      return getTodayHoliday();
    } catch (_) {
      return null;
    }
  }

  void _finish() {
    final quotaSec = _isCompletelyBlocked ? 0 : _quotaMinutes * 60;
    final weekendSec = _customWeekendQuota ? _weekendQuotaMinutes * 60 : null;
    final holidaySec = _customHolidayQuota ? _holidayQuotaMinutes * 60 : null;

    final scheduleMap = <String, dynamic>{
      'preset': _daysPreset,
      'days': _selectedDays.toList()..sort(),
      'weekend_quota_seconds': weekendSec,
      'time_window_enabled': _timeWindowEnabled,
      'time_window_start': _formatTimeOfDay(_timeWindowStart),
      'time_window_end': _formatTimeOfDay(_timeWindowEnd),
      'time_window_mode': _timeWindowMode,
      'notify_mode': _notifyEnabled ? _notifyMode : 'none',
      'notify_interval_mins': _notifyIntervalMins,
      'notify_remaining_mins': _notifyRemainingThresholds.toList()..sort(),
    };

    final result = BlockConfigResult(
      entityId: _selectedId,
      displayName: _selectedName,
      dailyQuotaSeconds: quotaSec,
      mode: widget.initialRule?.mode ?? widget.defaultMode,
      targetType: _targetType,
      pattern: _selectedPattern,
      isCompletelyBlocked: _isCompletelyBlocked,
      weekendQuotaSeconds: weekendSec,
      holidayQuotaSeconds: holidaySec,
      scheduleJson: jsonEncode(scheduleMap),
    );

    Navigator.pop(context, result);
  }

  Widget _buildAppIcon(InstalledAppDto app, {double size = 32}) {
    if (app.iconPath.isNotEmpty) {
      final f = File(app.iconPath);
      if (f.existsSync()) {
        final pathLower = app.iconPath.toLowerCase();
        if (pathLower.endsWith('.png') || pathLower.endsWith('.xpm')) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              f,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _defaultAppIcon(size),
            ),
          );
        }
      }
    }
    return _defaultAppIcon(size);
  }

  Widget _defaultAppIcon(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.purple.shade900.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.apps, size: size * 0.6, color: Colors.purpleAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final maxH = math.min(720.0, math.max(400.0, screenH * 0.9));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF141721),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _step == 0 ? _buildStepUnifiedGroupConfig() : _buildStepQuotaAndConfirm(),
        ),
      ),
    );
  }

  // ETAPA 0: Configuração Unificada de Sessão de Foco (Apps + Sites)
  Widget _buildStepUnifiedGroupConfig() {
    final totalSelected =
        _selectedAppKeys.length + _siteGroupItems.length + (widget.isWhitelist ? _ytTypes.length : 0);

    return Column(
      key: const ValueKey('step_unified_group_config'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    widget.isWhitelist ? Icons.verified_user : Icons.hub,
                    color: Colors.tealAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isWhitelist
                          ? (widget.initialWhitelistGroup != null ? tr.editarGrupoDeListaBranca : tr.novoGrupoDeListaBranca)
                          : (widget.dialogMode == BlockDialogMode.appsOnly
                              ? tr.adicionarAplicativosSitesAoGrupo
                              : (widget.initialRule != null ? tr.editarSessaoDeFoco : tr.criarSessaoDeFoco)),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        if (widget.isWhitelist) ...[
          const SizedBox(height: 4),
          Text(
            tr.appsESitesNaListaBranca,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _groupNameController,
          decoration: InputDecoration(
            hintText: widget.isWhitelist
                ? tr.digiteONomeDoGrupoDe
                : tr.digiteONomeDaSessaoDe,
            labelText: widget.isWhitelist ? tr.nomeDoGrupoDeListaBranca : tr.nomeDaSessaoDeFoco,
            prefixIcon: Icon(widget.isWhitelist ? Icons.shield : Icons.label, color: Colors.tealAccent),
            filled: true,
            fillColor: Colors.teal.withValues(alpha: 0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // Seletor de Sub-Aba: Aplicativos vs Sites (sem emojis)
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _groupSubTab == 0 ? Colors.purple.shade700 : Colors.white10,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.apps, size: 18),
                label: Text(tr.aplicativosP0(_selectedAppKeys.length)),
                onPressed: () => setState(() => _groupSubTab = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _groupSubTab == 1 ? Colors.blue.shade700 : Colors.white10,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.public, size: 18),
                label: Text(tr.sitesEPalavrasP0(_siteGroupItems.length)),
                onPressed: () => setState(() => _groupSubTab = 1),
              ),
            ),
            if (widget.isWhitelist) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _groupSubTab == 2 ? Colors.red.shade700 : Colors.white10,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.smart_display, size: 18),
                  label: Text(tr.youtubeP0(_ytTypes.length)),
                  onPressed: () => setState(() => _groupSubTab = 2),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // Conteúdo da Sub-Aba
        Expanded(
          child: _groupSubTab == 0
              ? _buildAppsSection()
              : (_groupSubTab == 2 && widget.isWhitelist ? _buildYoutubeTypesSection() : _buildSitesSection()),
        ),

        const SizedBox(height: 10),

        // Barra inferior com resumo e botão de avançar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers, size: 18, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tr.p0AppsP1Sites(_selectedAppKeys.length, _siteGroupItems.length),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: totalSelected > 0 ? Colors.teal.shade700 : Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: Icon(
                  widget.isWhitelist
                      ? Icons.check
                      : (widget.dialogMode == BlockDialogMode.appsOnly ? Icons.save : Icons.arrow_forward),
                  size: 18,
                ),
                label: Text(
                  widget.isWhitelist
                      ? tr.salvarListaBranca
                      : (widget.dialogMode == BlockDialogMode.appsOnly
                          ? tr.salvarAppsNoGrupo
                          : tr.avancarTempoDeTelaRegras),
                ),
                onPressed: totalSelected == 0
                    ? null
                    : (widget.isWhitelist
                        ? _saveWhitelistDirectly
                        : (widget.dialogMode == BlockDialogMode.appsOnly
                            ? _saveAppsDirectly
                            : _onUnifiedGroupContinue)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppsSection() {
    final availableTags = _getAllAvailableTags();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _groupSearchController,
                decoration: InputDecoration(
                  hintText: tr.buscarPorNomeExecutavelOuTag,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _selectAllApps,
              child: Text(tr.selecionarTudo),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: _deselectAllApps,
              child: Text(tr.limpar),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Barra horizontal de filtro rápido por Tags
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: availableTags.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, idx) {
              final tag = availableTags[idx];
              final isSelected = _selectedTagFilter == tag;
              return ChoiceChip(
                label: Text(_tagLabel(tag), style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                visualDensity: VisualDensity.compact,
                selectedColor: Colors.purple.shade700,
                onSelected: (_) {
                  setState(() {
                    _selectedTagFilter = tag;
                    _applyAppFilters();
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: _loadingApps
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(tr.carregandoAplicativosInstalados, style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                )
              : _filteredGroupApps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tr.nenhumAplicativoEncontradoParaOFiltro, style: TextStyle(color: Colors.white54)),
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: Text(tr.limparFiltroDeTag),
                            onPressed: () {
                              setState(() {
                                _selectedTagFilter = 'Todas';
                                _groupSearchController.clear();
                                _applyAppFilters();
                              });
                            },
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredGroupApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredGroupApps[index];
                        final key = _appUniqueKey(app);
                        final isLocked = _isAppLocked(app);
                        final isSelected = isLocked || _selectedAppKeys.contains(key);
                        final appTags = _getAppTags(app);
                        return CheckboxListTile(
                          value: isSelected,
                          activeColor: isLocked ? Colors.tealAccent.shade700 : Colors.purpleAccent,
                          secondary: Opacity(
                            opacity: isLocked ? 0.6 : 1.0,
                            child: _buildAppIcon(app, size: 32),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  app.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isLocked ? Colors.white60 : Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLocked) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.tealAccent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    tr.jaNoGrupo,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.tealAccent,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _showAddCustomTagDialog(app),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.local_offer_outlined, size: 11, color: Colors.tealAccent),
                                      SizedBox(width: 3),
                                      Text(tr.tag, style: TextStyle(fontSize: 10, color: Colors.tealAccent)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.exec, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              if (appTags.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: appTags.map((t) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        t,
                                        style: const TextStyle(fontSize: 9, color: Colors.purpleAccent, fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                          onChanged: isLocked
                              ? null
                              : (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedAppKeys.add(key);
                                      _selectedAppObjects[key] = app;
                                    } else {
                                      _selectedAppKeys.remove(key);
                                      _selectedAppObjects.remove(key);
                                    }
                                  });
                                },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Lista Branca: tipos de vídeo do YouTube que não descontam tempo (com teto opcional).
  Widget _buildYoutubeTypesSection() {
    final types = getYoutubeContentTypes();
    return ListView(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            tr.videosDessesTiposNaoDescontamO,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ),
        for (final t in types)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _ytTypes.containsKey(t.id) ? Colors.redAccent : Colors.white12),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _ytTypes.containsKey(t.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _ytTypes[t.id] = null;
                    } else {
                      _ytTypes.remove(t.id);
                    }
                  }),
                ),
                Expanded(child: Text(t.label, style: const TextStyle(fontSize: 14))),
                if (_ytTypes.containsKey(t.id))
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      key: ValueKey('cap_${t.id}'),
                      initialValue: _ytTypes[t.id]?.toString() ?? '',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: tr.tetoMinDia,
                        hintText: tr.semTeto,
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        setState(() => _ytTypes[t.id] = (n != null && n > 0) ? n : null);
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSitesSection() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _siteInputController,
                  onChanged: (_) {
                    if (_duplicateSiteNotice != null) {
                      setState(() => _duplicateSiteNotice = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: tr.digiteDominioOuPalavraChaveEx,
                    prefixIcon: const Icon(Icons.add_link, color: Colors.cyanAccent),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: _addSiteItem,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                ),
                icon: const Icon(Icons.add),
                label: Text(tr.adicionar),
                onPressed: () => _addSiteItem(_siteInputController.text),
              ),
            ],
          ),
          if (_duplicateSiteNotice != null) ...[
            const SizedBox(height: 8),
            Text(
              _duplicateSiteNotice!,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B202B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tr.sitesEPalavrasChaveAdicionadosP0(_siteGroupItems.length),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_siteGroupItems.any((item) => !_isSiteLocked(item)))
                      TextButton(
                        onPressed: () => setState(() {
                          _duplicateSiteNotice = null;
                          _siteGroupItems.removeWhere((item) => !_isSiteLocked(item));
                        }),
                        child: Text(
                          widget.dialogMode == BlockDialogMode.appsOnly && _lockedSiteItems.isNotEmpty
                              ? tr.limparNovos
                              : tr.limparTodos,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_siteGroupItems.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr.nenhumSiteOuPalavraChaveAdicionado,
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _siteGroupItems.map((item) {
                      final isLocked = _isSiteLocked(item);
                      return Chip(
                        backgroundColor: isLocked
                            ? Colors.teal.shade900.withValues(alpha: 0.45)
                            : Colors.blue.shade900.withValues(alpha: 0.5),
                        side: isLocked
                            ? BorderSide(color: Colors.tealAccent.withValues(alpha: 0.45))
                            : BorderSide.none,
                        avatar: isLocked
                            ? const Icon(Icons.lock_outline, size: 14, color: Colors.tealAccent)
                            : null,
                        label: Text(
                          isLocked ? tr.p0JaNoGrupo(item) : item,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        deleteIcon: isLocked
                            ? null
                            : const Icon(Icons.close, size: 16, color: Colors.white70),
                        onDeleted: isLocked
                            ? null
                            : () => setState(() => _siteGroupItems.remove(item)),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ETAPA 1: Definir Tempo de Tela com Relógio Digital, Janela de Horário e Notificações
  Widget _buildStepQuotaAndConfirm() {
    return SingleChildScrollView(
      key: const ValueKey('step_quota_confirm'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.dialogMode != BlockDialogMode.timeOnly) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step = 0),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.dialogMode == BlockDialogMode.timeOnly
                      ? tr.editarTempoDeBloqueioP0(_selectedName)
                      : tr.tempoDeTelaP0(_selectedName),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr.sessaoP0(_selectedName), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tr.grupoDeFocoUnificado,
                        style: TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr.p0AplicativosEP1SitesInclusos(_selectedAppKeys.length, _siteGroupItems.length),
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  tr.todosOsAplicativosESitesDesta,
                  style: TextStyle(color: Colors.teal.shade200, fontSize: 11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: Colors.tealAccent),
              SizedBox(width: 8),
              Text(
                tr.limiteDeTempoDeTelaRelogio,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Painel de Relógio Digital Interativo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isCompletelyBlocked
                    ? Colors.redAccent.withValues(alpha: 0.5)
                    : Colors.tealAccent.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  _isCompletelyBlocked ? tr.bloqueioTotal2 : _formatDigitalTime(_quotaMinutes),
                  style: TextStyle(
                    fontSize: _isCompletelyBlocked ? 28 : 44,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: _isCompletelyBlocked ? 2 : 4,
                    color: _isCompletelyBlocked ? Colors.redAccent : Colors.tealAccent,
                  ),
                ),
                Text(
                  _isCompletelyBlocked
                      ? tr.nenhumAcessoPermitidoDuranteODia
                      : tr.p0DeUsoPermitido(_formatReadableTime(_quotaMinutes)),
                  style: TextStyle(
                    fontSize: 12,
                    color: _isCompletelyBlocked ? Colors.red.shade200 : Colors.white70,
                  ),
                ),
                const SizedBox(height: 12),

                // Seletor de Tambor (Cupertino Wheel Picker)
                if (!_isCompletelyBlocked) ...[
                  SizedBox(
                    height: 120,
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        brightness: Brightness.dark,
                        textTheme: CupertinoTextThemeData(
                          pickerTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontFamily: 'monospace'),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Tambor de Horas (0 a 12 horas)
                          SizedBox(
                            width: 90,
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(initialItem: _quotaMinutes ~/ 60),
                              itemExtent: 36,
                              onSelectedItemChanged: (h) {
                                setState(() {
                                  final m = _quotaMinutes % 60;
                                  _quotaMinutes = (h * 60 + m).clamp(1, 720);
                                });
                              },
                              children: List.generate(13, (i) => Center(child: Text('$i h'))),
                            ),
                          ),
                          const Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                          // Tambor de Minutos (0 a 55 min em passos de 5)
                          SizedBox(
                            width: 90,
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(initialItem: (_quotaMinutes % 60) ~/ 5),
                              itemExtent: 36,
                              onSelectedItemChanged: (idx) {
                                setState(() {
                                  final h = _quotaMinutes ~/ 60;
                                  final m = idx * 5;
                                  _quotaMinutes = (h * 60 + m).clamp(1, 720);
                                });
                              },
                              children: List.generate(12, (i) => Center(child: Text('${i * 5} m'))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                CheckboxListTile(
                  title: Text(tr.bloquearTotalmente0MinDeTempo, style: TextStyle(fontSize: 13)),
                  subtitle: Text(tr.impedeQualquerInicializacaoDoGrupoImediatamente, style: TextStyle(fontSize: 11, color: Colors.white54)),
                  value: _isCompletelyBlocked,
                  activeColor: Colors.redAccent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _isCompletelyBlocked = val ?? false),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Finais de Semana Personalizados
          SwitchListTile(
            title: Text(tr.tempoDeTelaDiferenciadoNoFinal, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text(tr.permiteConfigurarMaisTempoParaSabado, style: TextStyle(fontSize: 11, color: Colors.white54)),
            value: _customWeekendQuota,
            activeThumbColor: Colors.tealAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _customWeekendQuota = val),
          ),
          if (_customWeekendQuota) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr.tempoFimDeSemanaP0(_formatReadableTime(_weekendQuotaMinutes)), style: const TextStyle(fontSize: 12)),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      value: _weekendQuotaMinutes.toDouble(),
                      min: 15,
                      max: 480,
                      divisions: 31,
                      activeColor: Colors.tealAccent,
                      onChanged: (v) => setState(() => _weekendQuotaMinutes = v.toInt()),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Feriados (prioridade: feriado > fim de semana > dia útil)
          SwitchListTile(
            title: Text(tr.tempoDeTelaDiferenciadoEmFeriados, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text(
              tr.valeNosFeriadosNacionaisENas(_todayHolidaySafe() != null ? tr.hojeP0('${_todayHolidaySafe()}') : ''),
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            value: _customHolidayQuota,
            activeThumbColor: Colors.orangeAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _customHolidayQuota = val),
          ),
          if (_customHolidayQuota) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr.tempoEmFeriadosP0(_formatReadableTime(_holidayQuotaMinutes)), style: const TextStyle(fontSize: 12)),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      value: _holidayQuotaMinutes.toDouble(),
                      min: 15,
                      max: 720,
                      divisions: 47,
                      activeColor: Colors.orangeAccent,
                      onChanged: (v) => setState(() => _holidayQuotaMinutes = v.toInt()),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr.diasDaSemanaAtivos, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Wrap(
                spacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(tr.todos, style: TextStyle(fontSize: 10)),
                    selected: _daysPreset == 'ALL',
                    onSelected: (_) => _setPreset('ALL'),
                  ),
                  ChoiceChip(
                    label: Text(tr.diasUteis, style: TextStyle(fontSize: 10)),
                    selected: _daysPreset == 'WEEKDAYS',
                    onSelected: (_) => _setPreset('WEEKDAYS'),
                  ),
                  ChoiceChip(
                    label: Text(tr.finsDeSemana, style: TextStyle(fontSize: 10)),
                    selected: _daysPreset == 'WEEKENDS',
                    onSelected: (_) => _setPreset('WEEKENDS'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Botões de Dias Compactos e Retangulares
          Row(
            children: [
              _buildDayRectangle(1, tr.seg),
              _buildDayRectangle(2, tr.ter),
              _buildDayRectangle(3, tr.qua),
              _buildDayRectangle(4, tr.qui),
              _buildDayRectangle(5, tr.sex),
              _buildDayRectangle(6, tr.sab),
              _buildDayRectangle(7, tr.dom),
            ],
          ),

          const SizedBox(height: 18),

          // JANELA DE HORÁRIO (Time Window)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _timeWindowEnabled ? Colors.orangeAccent.withValues(alpha: 0.4) : Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: Text(tr.bloqueioPorJanelaDeHorario, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(tr.bloqueiaOGrupoDentroDeUm, style: TextStyle(fontSize: 11, color: Colors.white54)),
                  value: _timeWindowEnabled,
                  activeThumbColor: Colors.orangeAccent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _timeWindowEnabled = val),
                ),
                if (_timeWindowEnabled) ...[
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16, color: Colors.orangeAccent),
                        label: Text(tr.inicioP0(_formatTimeOfDay(_timeWindowStart))),
                        onPressed: () => _pickTime(isStart: true),
                      ),
                      const Icon(Icons.arrow_forward, size: 16, color: Colors.white54),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_filled, size: 16, color: Colors.orangeAccent),
                        label: Text(tr.fimP0(_formatTimeOfDay(_timeWindowEnd))),
                        onPressed: () => _pickTime(isStart: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(tr.modo, style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(tr.bloquearDentro),
                        selected: _timeWindowMode == 'BLOCK_INSIDE',
                        onSelected: (_) => setState(() => _timeWindowMode = 'BLOCK_INSIDE'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(tr.permitirSomenteDentro),
                        selected: _timeWindowMode == 'ALLOW_INSIDE',
                        onSelected: (_) => setState(() => _timeWindowMode = 'ALLOW_INSIDE'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // SISTEMA DE NOTIFICAÇÕES (Toggles Independentes)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_notifyRemaining || _notifyPeriodic) ? Colors.tealAccent.withValues(alpha: 0.4) : Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: Text(tr.notificacaoPorTempoRestante, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(tr.avisaAos155E1, style: TextStyle(fontSize: 11, color: Colors.white54)),
                  value: _notifyRemaining,
                  activeThumbColor: Colors.tealAccent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() {
                    _notifyRemaining = val;
                    _notifyEnabled = _notifyRemaining || _notifyPeriodic;
                    _notifyMode = (_notifyRemaining && _notifyPeriodic)
                        ? 'both'
                        : (_notifyRemaining ? 'remaining' : (_notifyPeriodic ? 'periodic' : 'none'));
                  }),
                ),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  title: Text(tr.notificacaoPeriodica, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(tr.emiteLembretesRegularesEnquantoASessao, style: TextStyle(fontSize: 11, color: Colors.white54)),
                  value: _notifyPeriodic,
                  activeThumbColor: Colors.tealAccent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() {
                    _notifyPeriodic = val;
                    _notifyEnabled = _notifyRemaining || _notifyPeriodic;
                    _notifyMode = (_notifyRemaining && _notifyPeriodic)
                        ? 'both'
                        : (_notifyRemaining ? 'remaining' : (_notifyPeriodic ? 'periodic' : 'none'));
                  }),
                ),
                if (_notifyPeriodic) ...[
                  const SizedBox(height: 8),
                  Text(tr.intervaloDaNotificacaoPeriodica, style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [1, 5, 10, 15, 30, 60].map((mins) {
                      return ChoiceChip(
                        label: Text(tr.aCadaP0Min(mins)),
                        selected: _notifyIntervalMins == mins,
                        onSelected: (_) => setState(() => _notifyIntervalMins = mins),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.teal.shade700,
            ),
            onPressed: _finish,
            child: Text(
              tr.salvarGrupoDeFoco,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayRectangle(int day, String label) {
    final isSelected = _selectedDays.contains(day);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _toggleDay(day),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 38,
            decoration: BoxDecoration(
              color: isSelected ? Colors.tealAccent.shade700 : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
