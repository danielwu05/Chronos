import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show themeModeNotifier;
import '../services/browser_extension_installer.dart';
import '../services/chronos_guard_service.dart';
import '../services/notification_service.dart';
import '../services/web_block_server.dart';
import '../src/rust/api/simple.dart';
import 'anti_cheat_dialog.dart';
import 'browser_protection_panel.dart';

class _LauncherSuggestionOption {
  final String value;
  final String label;
  final String? secondaryLabel;
  final String? imageUrl;

  const _LauncherSuggestionOption({
    required this.value,
    required this.label,
    this.secondaryLabel,
    this.imageUrl,
  });
}

class GeneralSettingsView extends StatefulWidget {
  final VoidCallback onResetOnboarding;
  final VoidCallback onSettingsChanged;

  const GeneralSettingsView({
    super.key,
    required this.onResetOnboarding,
    required this.onSettingsChanged,
  });

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  final NotificationService _notifications = NotificationService();
  List<DetectedBrowser> _browsers = [];
  AntiCheatStateDto? _antiCheatState;
  OnboardingStateDto? _onboardingState;
  ChronosGuardStatus? _guardStatus;
  FocusFiltersDto? _focusFilters;
  String _currentTheme = 'dark';
  bool _loading = true;
  bool _installingExtensions = false;
  bool _removingExtensions = false;
  bool _extensionsRemovedByUser = false;

  final TextEditingController _launcherTagCtrl = TextEditingController();
  final TextEditingController _launcherNameCtrl = TextEditingController();
  String _primaryLanguage = 'pt-BR';
  Map<String, String> _tagDisplayMap = const {};
  List<SteamTagSuggestionDto> _popularTagItems = const [];
  List<SteamTagSuggestionDto> _tagAutocomplete = const [];
  List<SteamGameSuggestionDto> _gameAutocomplete = const [];
  bool _loadingTagAutocomplete = false;
  bool _loadingGameAutocomplete = false;
  Timer? _tagDebounce;
  Timer? _gameDebounce;
  Timer? _nukeExpiryTimer;
  List<LauncherGameDto> _installedGames = const [];
  bool _loadingGames = false;
  bool _gamesExpanded = false;
  bool _configuringLauncherProxy = false;

  @override
  void initState() {
    super.initState();
    antiCheatStateRevision.addListener(_onExternalAntiCheatChanged);
    _loadAll();
    getAntiCheatState().then(_scheduleNukeRefresh).catchError((_) {});
  }

  @override
  void dispose() {
    antiCheatStateRevision.removeListener(_onExternalAntiCheatChanged);
    _nukeExpiryTimer?.cancel();
    _tagDebounce?.cancel();
    _gameDebounce?.cancel();
    _launcherTagCtrl.dispose();
    _launcherNameCtrl.dispose();
    super.dispose();
  }

  void _scheduleNukeRefresh(AntiCheatStateDto? ac) {
    _nukeExpiryTimer?.cancel();
    _nukeExpiryTimer = null;
    if (!mounted || ac == null || !ac.isActive || ac.mode != 'NUKE') return;
    final delaySecs = ac.nukeRemainingSeconds > 0 ? ac.nukeRemainingSeconds + 1 : 1;
    _nukeExpiryTimer = Timer(Duration(seconds: delaySecs), () {
      notifyAntiCheatStateChanged();
    });
  }

  void _onExternalAntiCheatChanged() {
    if (!mounted) return;
    _refreshAntiCheatAndFilters();
  }

  Future<void> _refreshAntiCheatAndFilters() async {
    try {
      final results = await Future.wait<dynamic>([
        getAntiCheatState(),
        getFocusFilters(),
      ]);
      final ac = results[0] as AntiCheatStateDto;
      final ff = results[1] as FocusFiltersDto;
      if (!mounted) return;
      setState(() {
        _antiCheatState = ac;
        _focusFilters = ff;
      });
      _scheduleNukeRefresh(ac);
      await _refreshTagDisplayMap(ff.launcherBlockedTags);
    } catch (_) {}
  }

  Future<void> _refreshTagDisplayMap(List<String> tags) async {
    if (tags.isEmpty) {
      if (mounted) setState(() => _tagDisplayMap = const {});
      return;
    }
    try {
      final entries = await getTagDisplayMap(tags: tags, lang: _primaryLanguage);
      if (mounted) {
        setState(() {
          _tagDisplayMap = {
            for (final e in entries) e.canonicalEn: e.displayName,
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLauncherSuggestions() async {
    try {
      final items = await getPopularSteamTagsLocalized(lang: _primaryLanguage);
      if (mounted && items.isNotEmpty) {
        setState(() => _popularTagItems = items);
      }
    } catch (_) {}
  }

  void _onLauncherTagQueryChanged(String query) {
    _tagDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _tagAutocomplete = const [];
        _loadingTagAutocomplete = false;
      });
      return;
    }
    setState(() => _loadingTagAutocomplete = true);
    _tagDebounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final results = await searchSteamTagsAutocomplete(
          query: trimmed,
          lang: _primaryLanguage,
        );
        if (!mounted || _launcherTagCtrl.text.trim() != trimmed) return;
        setState(() {
          _tagAutocomplete = results;
          _loadingTagAutocomplete = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingTagAutocomplete = false);
      }
    });
  }

  void _onLauncherGameQueryChanged(String query) {
    _gameDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _gameAutocomplete = const [];
        _loadingGameAutocomplete = false;
      });
      return;
    }
    setState(() => _loadingGameAutocomplete = true);
    _gameDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await searchSteamGamesAutocomplete(
          query: trimmed,
          lang: _primaryLanguage,
        );
        if (!mounted || _launcherNameCtrl.text.trim() != trimmed) return;
        setState(() {
          _gameAutocomplete = results;
          _loadingGameAutocomplete = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingGameAutocomplete = false);
      }
    });
  }

  Future<void> _changePrimaryLanguage(String lang) async {
    if (_primaryLanguage == lang) return;
    setState(() => _primaryLanguage = lang);
    final res = await setPrimaryLanguage(lang: lang);
    if (!res.success) {
      _showSnack(res.message, false);
      return;
    }
    WebBlockServer.nudgeObservers();
    await _loadLauncherSuggestions();
    await _refreshTagDisplayMap(_focusFilters?.launcherBlockedTags ?? const []);
    if (_launcherTagCtrl.text.trim().isNotEmpty) {
      _onLauncherTagQueryChanged(_launcherTagCtrl.text);
    }
    if (_launcherNameCtrl.text.trim().length >= 2) {
      _onLauncherGameQueryChanged(_launcherNameCtrl.text);
    }
    _showSnack(
      lang == 'en-US'
          ? 'Idioma principal Steam API definido para English (US).'
          : 'Idioma principal Steam API definido para Português (Brasil).',
      true,
    );
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final browsers = await BrowserExtensionInstaller.detectBrowsers();
      final antiCheat = await getAntiCheatState();
      final onboarding = await getOnboardingState();
      final guardStatus = await ChronosGuardService.checkStatus();
      String primaryLanguage = 'pt-BR';
      try {
        primaryLanguage = await getPrimaryLanguage();
      } catch (_) {}
      FocusFiltersDto? focusFilters;
      try {
        focusFilters = await getFocusFilters();
      } catch (_) {}
      String themeMode = 'dark';
      try {
        themeMode = await getThemeMode();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _browsers = browsers;
          _antiCheatState = antiCheat;
          _onboardingState = onboarding;
          _guardStatus = guardStatus;
          _primaryLanguage = primaryLanguage;
          _focusFilters = focusFilters;
          _currentTheme = themeMode;
          _extensionsRemovedByUser = BrowserExtensionInstaller.hasUserRemovedExtensionFlag();
          _loading = false;
        });
        _loadLauncherSuggestions();
        if (focusFilters != null && focusFilters.launcherBlockedTags.isNotEmpty) {
          _refreshTagDisplayMap(focusFilters.launcherBlockedTags);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeTheme(String mode) async {
    setState(() => _currentTheme = mode);
    final res = await setThemeMode(mode: mode);
    _showSnack(res.message, res.success);
    if (mode == 'light') {
      themeModeNotifier.value = ThemeMode.light;
    } else if (mode == 'dark') {
      themeModeNotifier.value = ThemeMode.dark;
    } else {
      themeModeNotifier.value = ThemeMode.system;
    }
    widget.onSettingsChanged();
  }

  Future<void> _handleRemoveExtensionsWithAntiCheat() async {
    if (_removingExtensions) return;
    final state = await getAntiCheatState();
    if (!mounted) return;

    if (state.isActive && state.mode == 'NUKE') {
      _showSnack(
        'Modo Nuke ativo: remoção da extensão bloqueada até o tempo expirar.',
        false,
      );
      return;
    }

    if (state.isActive) {
      final unlocked = await AntiCheatDialog.showUnlockChallenge(
        context,
        onStateChanged: () {
          widget.onSettingsChanged();
          _loadAll();
        },
      );
      if (!unlocked || !mounted) {
        _showSnack(
          'Remoção cancelada: conclua a verificação Anti-Cheat para remover a extensão.',
          false,
        );
        return;
      }
    }

    final postState = await getAntiCheatState();
    if (postState.isActive) {
      _showSnack('Anti-Cheat ainda ativo. Remoção bloqueada.', false);
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Remover Extensão & Políticas?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Verificação Anti-Cheat concluída. Isso removerá a extensão Chronos, os links External Extensions e o Chronos Guard (políticas de Chrome/Chromium/Firefox) de todos os navegadores até você reinstalar.\n\nConfirmar remoção?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover de Todos os Navegadores'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingExtensions = true);
    final res = await ChronosGuardService.verifyAntiCheatAndUninstall();
    await _loadAll();
    if (!mounted) return;
    setState(() => _removingExtensions = false);
    _showSnack(res.message, res.success);
  }

  void _showSnack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.teal.shade700 : Colors.redAccent.shade700,
      ),
    );
  }

  static const FocusFiltersDto _defaultFocusFilters = FocusFiltersDto(
    blockShorts: false,
    grayscaleMode: false,
    educationalOnly: false,
    blockFeed: false,
    blockComments: false,
    blockNotifications: false,
    ytBlockShorts: true,
    ytEducationalMode: false,
    ytBlockSidebar: false,
    ytBlockComments: false,
    igBlockReels: true,
    igBlockFeed: false,
    igBlockComments: false,
    ttBlockFeed: true,
    rdBlockFeed: false,
    rdBlockComments: false,
    twBlockFeed: false,
    twBlockTrends: false,
    liBlockFeed: false,
    globalGrayscale: false,
    globalBlockNotifications: false,
    hudAlpha: 0.94,
    hudHideToEye: true,
    hudScale: 1.0,
    launcherFilterEnabled: true,
    launcherBlockedTags: <String>[],
    launcherBlockedNames: <String>[],
  );

  FocusFiltersDto _buildUpdatedFilters({
    bool? ytBlockShorts,
    bool? ytEducationalMode,
    bool? ytBlockSidebar,
    bool? ytBlockComments,
    bool? igBlockReels,
    bool? igBlockFeed,
    bool? igBlockComments,
    bool? ttBlockFeed,
    bool? rdBlockFeed,
    bool? rdBlockComments,
    bool? twBlockFeed,
    bool? twBlockTrends,
    bool? liBlockFeed,
    bool? globalGrayscale,
    bool? globalBlockNotifications,
    double? hudAlpha,
    bool? hudHideToEye,
    double? hudScale,
    bool? launcherFilterEnabled,
    List<String>? launcherBlockedTags,
    List<String>? launcherBlockedNames,
  }) {
    final current = _focusFilters ?? _defaultFocusFilters;
    final nextGlobalGrayscale = globalGrayscale ?? current.globalGrayscale;
    final nextGlobalNotifications =
        globalBlockNotifications ?? current.globalBlockNotifications;
    final rawAlpha = hudAlpha ?? current.hudAlpha;
    final nextHudAlpha = rawAlpha.isFinite ? rawAlpha.clamp(0.15, 1.0) : 0.94;
    final rawScale = hudScale ?? current.hudScale;
    final nextHudScale = rawScale.isFinite ? rawScale.clamp(0.70, 1.60) : 1.0;

    // Legacy coarse flags stay false so per-platform toggles remain isolated.
    return FocusFiltersDto(
      blockShorts: false,
      grayscaleMode: nextGlobalGrayscale,
      educationalOnly: false,
      blockFeed: false,
      blockComments: false,
      blockNotifications: nextGlobalNotifications,

      ytBlockShorts: ytBlockShorts ?? current.ytBlockShorts,
      ytEducationalMode: ytEducationalMode ?? current.ytEducationalMode,
      ytBlockSidebar: ytBlockSidebar ?? current.ytBlockSidebar,
      ytBlockComments: ytBlockComments ?? current.ytBlockComments,

      igBlockReels: igBlockReels ?? current.igBlockReels,
      igBlockFeed: igBlockFeed ?? current.igBlockFeed,
      igBlockComments: igBlockComments ?? current.igBlockComments,

      ttBlockFeed: ttBlockFeed ?? current.ttBlockFeed,

      rdBlockFeed: rdBlockFeed ?? current.rdBlockFeed,
      rdBlockComments: rdBlockComments ?? current.rdBlockComments,

      twBlockFeed: twBlockFeed ?? current.twBlockFeed,
      twBlockTrends: twBlockTrends ?? current.twBlockTrends,

      liBlockFeed: liBlockFeed ?? current.liBlockFeed,

      globalGrayscale: nextGlobalGrayscale,
      globalBlockNotifications: nextGlobalNotifications,

      hudAlpha: nextHudAlpha,
      hudHideToEye: hudHideToEye ?? current.hudHideToEye,
      hudScale: nextHudScale,
      launcherFilterEnabled: launcherFilterEnabled ?? current.launcherFilterEnabled,
      launcherBlockedTags: launcherBlockedTags ?? current.launcherBlockedTags,
      launcherBlockedNames: launcherBlockedNames ?? current.launcherBlockedNames,
    );
  }

  Future<void> _toggleFocusFilter({
    bool? ytBlockShorts,
    bool? ytEducationalMode,
    bool? ytBlockSidebar,
    bool? ytBlockComments,
    bool? igBlockReels,
    bool? igBlockFeed,
    bool? igBlockComments,
    bool? ttBlockFeed,
    bool? rdBlockFeed,
    bool? rdBlockComments,
    bool? twBlockFeed,
    bool? twBlockTrends,
    bool? liBlockFeed,
    bool? globalGrayscale,
    bool? globalBlockNotifications,
    double? hudAlpha,
    bool? hudHideToEye,
    double? hudScale,
    bool? launcherFilterEnabled,
    List<String>? launcherBlockedTags,
    List<String>? launcherBlockedNames,
  }) async {
    final current = _focusFilters ?? _defaultFocusFilters;
    final updated = _buildUpdatedFilters(
      ytBlockShorts: ytBlockShorts,
      ytEducationalMode: ytEducationalMode,
      ytBlockSidebar: ytBlockSidebar,
      ytBlockComments: ytBlockComments,
      igBlockReels: igBlockReels,
      igBlockFeed: igBlockFeed,
      igBlockComments: igBlockComments,
      ttBlockFeed: ttBlockFeed,
      rdBlockFeed: rdBlockFeed,
      rdBlockComments: rdBlockComments,
      twBlockFeed: twBlockFeed,
      twBlockTrends: twBlockTrends,
      liBlockFeed: liBlockFeed,
      globalGrayscale: globalGrayscale,
      globalBlockNotifications: globalBlockNotifications,
      hudAlpha: hudAlpha,
      hudHideToEye: hudHideToEye,
      hudScale: hudScale,
      launcherFilterEnabled: launcherFilterEnabled,
      launcherBlockedTags: launcherBlockedTags,
      launcherBlockedNames: launcherBlockedNames,
    );

    setState(() => _focusFilters = updated);
    final res = await setFocusFilters(filters: updated);
    if (!res.success) {
      if (mounted) {
        setState(() => _focusFilters = current);
      }
      _showSnack(res.message, false);
      _loadAll();
    } else {
      WebBlockServer.nudgeObservers();
      try {
        final persisted = await getFocusFilters();
        if (mounted) {
          setState(() => _focusFilters = persisted);
          _refreshTagDisplayMap(persisted.launcherBlockedTags);
        }
      } catch (_) {}
      _showSnack('Filtros anti-distração salvos com sucesso!', true);
    }
  }

  bool get _isAntiCheatActive => _antiCheatState?.isActive == true;

  void _addLauncherTerm({required bool isTag, required String rawTerm}) {
    final clean = rawTerm.trim();
    if (clean.isEmpty) return;
    final current = _focusFilters ?? _defaultFocusFilters;
    final list = List<String>.from(
      isTag ? current.launcherBlockedTags : current.launcherBlockedNames,
    );
    final exists = list.any((t) => t.trim().toLowerCase() == clean.toLowerCase());
    if (exists) {
      _showSnack('"$clean" já está na lista.', false);
      return;
    }
    list.add(clean);
    if (isTag) {
      _launcherTagCtrl.clear();
      setState(() {
        _tagAutocomplete = const [];
        _loadingTagAutocomplete = false;
      });
      _toggleFocusFilter(launcherBlockedTags: list);
    } else {
      _launcherNameCtrl.clear();
      setState(() {
        _gameAutocomplete = const [];
        _loadingGameAutocomplete = false;
      });
      _toggleFocusFilter(launcherBlockedNames: list);
    }
  }

  void _removeLauncherTerm({required bool isTag, required String term}) {
    if (_isAntiCheatActive) {
      _showSnack(
        'Anti-Cheat ativo: desative o Anti-Cheat para remover tags ou nomes de jogos.',
        false,
      );
      return;
    }
    final current = _focusFilters ?? _defaultFocusFilters;
    final list = List<String>.from(
      isTag ? current.launcherBlockedTags : current.launcherBlockedNames,
    )..removeWhere((t) => t == term);
    if (isTag) {
      _toggleFocusFilter(launcherBlockedTags: list);
    } else {
      _toggleFocusFilter(launcherBlockedNames: list);
    }
  }

  Future<void> _refreshInstalledGames() async {
    if (_loadingGames) return;
    setState(() {
      _loadingGames = true;
      _gamesExpanded = true;
    });
    try {
      final games = await getInstalledLauncherGames(enrichViaSteam: true);
      if (mounted) {
        setState(() {
          _installedGames = games;
          _loadingGames = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGames = false);
    }
  }

  Future<void> _activateLauncherProxy(bool enable) async {
    if (_configuringLauncherProxy) return;
    if (!enable && _isAntiCheatActive) {
      _showSnack(
        'Anti-Cheat ativo: desative o Anti-Cheat para remover a proteção de loja dos launchers.',
        false,
      );
      return;
    }
    setState(() => _configuringLauncherProxy = true);
    try {
      final res = await configureLauncherStoreProxy(enable: enable);
      _showSnack(res.message, res.success);
    } finally {
      if (mounted) setState(() => _configuringLauncherProxy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings, color: Colors.tealAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configurações Gerais',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Ajustes de notificações, extensões locais, modo e segurança',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 0. Aparência e Modo de Tema
          _buildThemeCard(),
          const SizedBox(height: 16),

          // 1. Notificações de Desktop
          _buildCard(
            title: 'Notificações de Desktop',
            icon: Icons.notifications_active,
            iconColor: Colors.amberAccent,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Notificar Início de App Monitorado'),
                  subtitle: const Text(
                    'Exibe uma notificação no desktop avisando que o app em execução está sendo cronometrado.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  value: _notifications.notifyOnAppMonitored,
                  activeTrackColor: Colors.teal.shade800,
                  onChanged: (val) {
                    setState(() => _notifications.notifyOnAppMonitored = val);
                    _showSnack(
                      val ? 'Notificação de app monitorado ativada' : 'Notificação de app monitorado desativada',
                      true,
                    );
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                SwitchListTile(
                  title: const Text('Alertas de Tempo de Tela Restante'),
                  subtitle: const Text(
                    'Avisos automáticos quando restarem 15m, 5m e 1m antes do término do tempo de tela diário.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  value: _notifications.notifyRemaining,
                  activeTrackColor: Colors.teal.shade800,
                  onChanged: (val) {
                    setState(() => _notifications.notifyRemaining = val);
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                SwitchListTile(
                  title: const Text('Avisos Periódicos de Uso Ativo'),
                  subtitle: const Text(
                    'Lembretes em intervalos regulares (ex: a cada 15 min) com o tempo já utilizado.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  value: _notifications.notifyPeriodic,
                  activeTrackColor: Colors.teal.shade800,
                  onChanged: (val) {
                    setState(() => _notifications.notifyPeriodic = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Extensões & Proteção dos Navegadores (Fluxo Unificado)
          _buildCard(
            title: 'Extensões dos Navegadores (Bloqueio de Sites)',
            icon: Icons.extension,
            iconColor: Colors.blueAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Protege todos os navegadores do dispositivo offline: extensão local nos Chromium (Chrome, Chromium, Brave, Edge, Vivaldi, Opera) e Proxy Seletivo Focus + CA Local no Firefox.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                BrowserSetupFlowStepper(
                  hasPackages: _browsers.isNotEmpty || (_guardStatus?.isInstalled == true),
                  guardStatus: _guardStatus,
                  browsers: _browsers,
                ),
                const SizedBox(height: 14),
                const Text('Navegadores Detectados no Sistema:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                const SizedBox(height: 8),
                BrowserStatusChipsWrap(
                  browsers: _browsers,
                  onFeedback: _showSnack,
                  onShowChromeGuide: _showChromeGuideDialog,
                  onShowFirefoxGuide: _showFirefoxGuideDialog,
                  onRequestRelaunch: (browser) async {
                    await showConfirmRelaunchBrowsersDialog(
                      context,
                      [browser],
                      onCompleted: _loadAll,
                      onFeedback: _showSnack,
                    );
                  },
                ),
                if (_extensionsRemovedByUser) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Extensão removida após verificação Anti-Cheat. Clique abaixo para reinstalar em todos os navegadores.',
                            style: TextStyle(fontSize: 12, color: Colors.amberAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: _installingExtensions
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.security_update_good, size: 18),
                  label: Text(
                    _installingExtensions
                        ? 'Configurando Navegadores & Guard...'
                        : 'Instalar / Atualizar em Todos os Navegadores',
                  ),
                  onPressed: _installingExtensions
                      ? null
                      : () async {
                          setState(() => _installingExtensions = true);
                          try {
                            await runUnifiedBrowserSetupFlow(
                              context,
                              isAntiCheatActive: _antiCheatState?.isActive ?? false,
                              onRefresh: _loadAll,
                              onFeedback: _showSnack,
                              onPolkitFallback: _showGuardInstallDialog,
                            );
                          } finally {
                            if (mounted) setState(() => _installingExtensions = false);
                          }
                        },
                ),
                const SizedBox(height: 8),
                ManualBrowserFallbackTile(
                  browsers: _browsers,
                  onFeedback: _showSnack,
                  onShowChromeGuide: _showChromeGuideDialog,
                  onShowFirefoxGuide: _showFirefoxGuideDialog,
                  onShowGuardTerminal: _showGuardInstallDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2.3 Filtros de Conteúdo Anti-Distração (Estilo StayFocusd)
          _buildFocusFiltersCard(),
          const SizedBox(height: 16),

          // 2.5 Proteção Permanente do Sistema (Anti-Burla & Remoção Anti-Cheat)
          _buildCard(
            title: 'Proteção Permanente do Sistema (Anti-Burla de Navegadores)',
            icon: Icons.security,
            iconColor: Colors.tealAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_guardStatus?.isFullyActive == true) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user, color: Colors.tealAccent, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Proteção do Sistema Ativa & Trancada',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent, fontSize: 13),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Políticas forçadas ativas em Chrome/Chromium/Brave/Edge/Vivaldi/Opera (CRX3 assinado) '
                                'e Firefox Release (Proxy Seletivo Focus + CA Local + PAC, sem avisos em about:policies). '
                                'Remoção de extensão e navegação anônima estão bloqueadas.',
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.tealAccent),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Re-aplicar Políticas do Sistema'),
                        onPressed: () async {
                          final ok = await ChronosGuardService.applyPoliciesIfInstalled();
                          await _loadAll();
                          _showSnack(
                            ok ? 'Políticas do sistema verificadas e re-aplicadas!' : 'Falha ao re-aplicar políticas.',
                            ok,
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        icon: _removingExtensions
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : const Icon(Icons.delete_forever_outlined, size: 16),
                        label: Text(
                          _removingExtensions
                              ? 'Removendo...'
                              : 'Remover Extensão (Verificar Anti-Cheat)',
                        ),
                        onPressed: _removingExtensions ? null : _handleRemoveExtensionsWithAntiCheat,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    _guardStatus?.isGuardOutdated == true
                        ? 'O Chronos Guard instalado possui políticas antigas (ex.: ExtensionSettings sem assinatura no Firefox Release). Clique em "Instalar / Atualizar em Todos os Navegadores" acima para corrigir em 1 clique.'
                        : 'O Chronos Guard grava políticas permanentes em /etc/ (com sua autorização Polkit) para impedir desinstalação manual e navegação anônima. Use o botão principal acima para ativar em 1 clique.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
                        icon: const Icon(Icons.admin_panel_settings, size: 16),
                        label: Text(
                          _guardStatus?.isGuardOutdated == true
                              ? 'Atualizar Guard via Polkit (1 Clique)'
                              : 'Ativar Guard via Polkit (1 Clique)',
                        ),
                        onPressed: _installingExtensions
                            ? null
                            : () async {
                                setState(() => _installingExtensions = true);
                                try {
                                  await runUnifiedBrowserSetupFlow(
                                    context,
                                    isAntiCheatActive: _antiCheatState?.isActive ?? false,
                                    onRefresh: _loadAll,
                                    onFeedback: _showSnack,
                                    onPolkitFallback: _showGuardInstallDialog,
                                  );
                                } finally {
                                  if (mounted) setState(() => _installingExtensions = false);
                                }
                              },
                      ),
                      if (!_extensionsRemovedByUser)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          icon: _removingExtensions
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                                )
                              : const Icon(Icons.delete_forever_outlined, size: 16),
                          label: const Text('Remover Extensão (Verificar Anti-Cheat)'),
                          onPressed: _removingExtensions ? null : _handleRemoveExtensionsWithAntiCheat,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Modo do Aplicativo
          _buildCard(
            title: 'Modo do Aplicativo & Cadastro',
            icon: Icons.psychology,
            iconColor: Colors.purpleAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    final textColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modo Ativo: ${_onboardingState?.appMode == "PARENTAL" ? "Controle Parental" : "Auto-Controle"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _onboardingState?.appMode == 'PARENTAL'
                              ? 'Configurado com PIN e proteção parental de restrições.'
                              : 'Focado em autonomia, comprometimento pessoal e produtividade.',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    );

                    final button = OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Trocar Modo / Refazer Cadastro'),
                      onPressed: widget.onResetOnboarding,
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          textColumn,
                          const SizedBox(height: 12),
                          button,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: textColumn),
                        const SizedBox(width: 16),
                        button,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Anti-Cheat & Travamento
          _buildCard(
            title: 'Anti-Cheat & Proteção Contra Burlar',
            icon: Icons.shield,
            iconColor: Colors.deepOrangeAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _antiCheatState?.isActive == true
                                ? (_antiCheatState?.mode == 'NUKE'
                                    ? 'Modo Nuke Ativo (${_antiCheatState?.nukeRemainingSeconds}s restantes)'
                                    : 'Anti-Cheat Ativo (Desafio StayFocusd)')
                                : 'Anti-Cheat Desativado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _antiCheatState?.isActive == true ? Colors.deepOrangeAccent : Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Bloqueia modificações de regras, aumento de limites nos momentos de fraqueza e remoção de extensões.',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _antiCheatState?.isActive == true ? Colors.deepOrange.shade800 : Colors.teal.shade800,
                      ),
                      icon: const Icon(Icons.security, size: 16),
                      label: Text(_antiCheatState?.isActive == true ? 'Gerenciar Anti-Cheat' : 'Ativar Anti-Cheat'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AntiCheatDialog(
                            onStateChanged: () {
                              _loadAll();
                              widget.onSettingsChanged();
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Dados & Resets
          _buildCard(
            title: 'Gerenciamento de Dados Locais (Offline)',
            icon: Icons.storage,
            iconColor: Colors.cyanAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Todas as informações, regras e tempos de tela do Chronos são armazenados 100% localmente no seu computador.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.history_toggle_off, size: 16),
                      label: const Text('Zerar Consumo Diário de Hoje'),
                      onPressed: () async {
                        final res = await resetDailyUsage();
                        _showSnack(res.message, res.success);
                        widget.onSettingsChanged();
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Reiniciar Banco de Dados Completo'),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reiniciar Banco de Dados'),
                            content: const Text(
                              'Atenção: Isso irá apagar todas as regras de bloqueio criadas e redefinir o banco para o estado inicial. Deseja continuar?',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Zerar Tudo'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final res = await resetDatabaseFull();
                          _showSnack(res.message, res.success);
                          widget.onSettingsChanged();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuardInstallDialog() async {
    await ChronosGuardService.prepareStaging();
    final cmd = ChronosGuardService.getInstallCliCommand();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.tealAccent),
            SizedBox(width: 8),
            Text('Instalar Proteção Permanente'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta etapa configura os arquivos de política oficiais em /etc/ e ativa o serviço do systemd para travar as extensões em definitivo contra burla.',
                style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text('Como deseja prosseguir?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
              const SizedBox(height: 10),
              const Text(
                'Opção 1: Clique em "Abrir Terminal" para abrir uma janela onde você digita sua senha do sudo UMA vez.\n'
                'Opção 2: Ou copie o comando abaixo e execute no seu terminal favorito:',
                style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cmd,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.tealAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.tealAccent),
                      tooltip: 'Copiar Comando',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Comando copiado para a área de transferência!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Verificar Status'),
            onPressed: () async {
              await _loadAll();
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                _showSnack(
                  _guardStatus?.isFullyActive == true
                      ? 'Proteção do sistema ativa e confirmada!'
                      : 'Proteção ainda pendente de instalação.',
                  _guardStatus?.isFullyActive == true,
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Abrir Terminal'),
            onPressed: () async {
              final launched = await ChronosGuardService.launchInstallerInTerminal();
              if (mounted) {
                if (launched) {
                  _showSnack('Terminal aberto! Digite sua senha na janela para concluir.', true);
                } else {
                  Clipboard.setData(ClipboardData(text: cmd));
                  _showSnack('Não foi possível abrir o terminal automaticamente. Comando copiado!', false);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showChromeGuideDialog() async {
    final path = BrowserExtensionInstaller.getCanonicalExtensionDir();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.extension, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Ativar no Google Chrome'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O Google Chrome oficial bloqueia injeções ocultas por linha de comando por segurança. Para ativá-la, basta carregar a pasta local uma única vez (leva 10 segundos).',
                        style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Passo a passo rápido:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
              const SizedBox(height: 10),
              _buildStepItem('1', 'Clique no botão "Abrir Chrome" abaixo. O Chrome abrirá em chrome://extensions e o caminho da pasta será copiado.'),
              const SizedBox(height: 8),
              _buildStepItem('2', 'No Chrome, ative a chave "Modo do desenvolvedor" no canto superior direito.'),
              const SizedBox(height: 8),
              _buildStepItem('3', 'Clique no botão "Carregar sem compactação" (canto superior esquerdo).'),
              const SizedBox(height: 8),
              _buildStepItem('4', 'Pressione Ctrl+V ou selecione a pasta da extensão e confirme.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        path,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.tealAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.tealAccent),
                      tooltip: 'Copiar Caminho',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: path));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Caminho copiado para a área de transferência!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Baixar .zip'),
            onPressed: () async {
              final zip = await BrowserExtensionInstaller.exportExtensionZipToDownloads();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(zip != null
                        ? 'Arquivo salvo em: $zip'
                        : 'Erro ao gerar zip para Downloads.'),
                    backgroundColor: zip != null ? Colors.teal.shade700 : Colors.red.shade800,
                  ),
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent.shade700),
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: const Text('Abrir Chrome'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              await BrowserExtensionInstaller.launchGoogleChromeWithExtensionGuide();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chrome aberto! Caminho copiado para a área de transferência.'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showFirefoxGuideDialog() {
    final path = BrowserExtensionInstaller.getFirefoxExtensionDir();
    final manifestPath = '$path/manifest.json';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.extension, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Ativar Extensão no Firefox', style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No Firefox Release padrão, a Mozilla exige assinatura para .xpi externos — por isso a proteção permanente do Chronos funciona pelo Proxy Seletivo Local + Certificado CA via Chronos Guard. Para Firefox ESR/Dev/LibreWolf/Zen ou testes temporários em about:debugging, use o .xpi:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              _buildStepItem('1', 'Clique no botão "Abrir Firefox" abaixo para ir direto à aba de depuração.'),
              const SizedBox(height: 8),
              _buildStepItem('2', 'Clique no botão "Carregar extensão temporária...".'),
              const SizedBox(height: 8),
              _buildStepItem('3', 'Selecione o arquivo "manifest.json" na pasta abaixo ou o arquivo .xpi em ~/Downloads.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        manifestPath,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.orangeAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.orangeAccent),
                      tooltip: 'Copiar Caminho',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: manifestPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Caminho do manifest.json copiado!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Baixar .xpi'),
            onPressed: () async {
              final xpi = await BrowserExtensionInstaller.exportFirefoxExtensionZipToDownloads();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(xpi != null
                        ? 'Arquivo salvo em: $xpi'
                        : 'Erro ao gerar xpi para Downloads.'),
                    backgroundColor: xpi != null ? Colors.teal.shade700 : Colors.red.shade800,
                  ),
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: const Text('Abrir Firefox'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: manifestPath));
              await BrowserExtensionInstaller.launchFirefoxWithExtensionGuide();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Firefox aberto! Caminho copiado para a área de transferência.'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildStepItem(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
          ),
          child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3)),
        ),
      ],
    );
  }

  Widget _buildThemeCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _buildCard(
      title: 'Aparência & Modo de Tema',
      icon: Icons.palette_outlined,
      iconColor: Colors.cyanAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personalize o tema visual do Chronos. O Modo Claro é otimizado para ambientes claros com alto contraste, e o Modo Escuro reduz o cansaço visual.',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'dark',
                icon: Icon(Icons.dark_mode_outlined, size: 18),
                label: Text('Modo Escuro'),
              ),
              ButtonSegment(
                value: 'light',
                icon: Icon(Icons.light_mode_outlined, size: 18),
                label: Text('Modo Claro'),
              ),
              ButtonSegment(
                value: 'system',
                icon: Icon(Icons.settings_brightness_outlined, size: 18),
                label: Text('Sistema'),
              ),
            ],
            selected: {_currentTheme},
            onSelectionChanged: (val) {
              if (val.isNotEmpty) {
                _changeTheme(val.first);
              }
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Idioma Principal (Tags & Autocomplete Steam API)',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'As tags são enviadas em inglês para a Steam API e exibidas aqui e nas extensões no seu idioma selecionado.',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'pt-BR',
                icon: Icon(Icons.translate_outlined, size: 17),
                label: Text('Português (BR)'),
              ),
              ButtonSegment(
                value: 'en-US',
                icon: Icon(Icons.language_outlined, size: 17),
                label: Text('English (US)'),
              ),
            ],
            selected: {_primaryLanguage},
            onSelectionChanged: (val) {
              if (val.isNotEmpty) {
                _changePrimaryLanguage(val.first);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFocusFiltersCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filters = _focusFilters ?? _defaultFocusFilters;
    final safeAlpha = filters.hudAlpha.isFinite ? filters.hudAlpha.clamp(0.15, 1.0) : 0.94;
    final safeScale = filters.hudScale.isFinite ? filters.hudScale.clamp(0.70, 1.60) : 1.0;

    return _buildCard(
      title: 'Filtros de Conteúdo & Anti-Distração por Plataforma (Estilo StayFocusd)',
      icon: Icons.filter_alt_outlined,
      iconColor: Colors.deepPurpleAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configure filtros de CSS e HTML específicos para cada aplicativo ou rede social. Elimine gatilhos de dopamina sem precisar bloquear os sites por completo.',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),

          // 🌐 DETOX GLOBAL (PRIMEIRO)
          _buildPlatformHeader('Detox Global (Todos os Sites)', Icons.public, Colors.tealAccent),
          _buildFilterSwitch(
            title: 'Modo Preto e Branco (Grayscale Detox)',
            subtitle: 'Aplica escala de cinza em todas as páginas para desestimular consumo compulsivo visual.',
            icon: Icons.monochrome_photos,
            value: filters.globalGrayscale,
            onChanged: (val) => _toggleFocusFilter(globalGrayscale: val),
          ),
          _buildFilterSwitch(
            title: 'Bloquear Notificações e Badges',
            subtitle: 'Remove sinos vermelhos e alertas numéricos em todos os sites para evitar interrupções.',
            icon: Icons.notifications_off_outlined,
            value: filters.globalBlockNotifications,
            onChanged: (val) => _toggleFocusFilter(globalBlockNotifications: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🔴 YOUTUBE FOCUS
          _buildPlatformHeader('YouTube Focus', Icons.play_circle_filled, Colors.redAccent),
          _buildFilterSwitch(
            title: 'Bloquear YouTube Shorts',
            subtitle: 'Oculta carrosséis de Shorts na home, na busca e na barra lateral.',
            icon: Icons.movie_filter_outlined,
            value: filters.ytBlockShorts,
            onChanged: (val) => _toggleFocusFilter(ytBlockShorts: val),
          ),
          _buildFilterSwitch(
            title: 'Modo Educativo (Ocultar Feed da Home)',
            subtitle: 'Oculta todas as recomendações algorítmicas da página inicial do YouTube.',
            icon: Icons.school_outlined,
            value: filters.ytEducationalMode,
            onChanged: (val) => _toggleFocusFilter(ytEducationalMode: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Vídeos Relacionados (Barra Lateral)',
            subtitle: 'Remove sugestões de vídeos ao lado do reprodutor para evitar distrações.',
            icon: Icons.view_sidebar_outlined,
            value: filters.ytBlockSidebar,
            onChanged: (val) => _toggleFocusFilter(ytBlockSidebar: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Comentários do YouTube',
            subtitle: 'Oculta toda a seção de comentários em qualquer vídeo.',
            icon: Icons.speaker_notes_off_outlined,
            value: filters.ytBlockComments,
            onChanged: (val) => _toggleFocusFilter(ytBlockComments: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 📸 INSTAGRAM FOCUS
          _buildPlatformHeader('Instagram Focus', Icons.camera_alt, Colors.pinkAccent),
          _buildFilterSwitch(
            title: 'Bloquear Instagram Reels',
            subtitle: 'Remove a aba e o carrossel de vídeos curtos Reels no Instagram Web.',
            icon: Icons.slow_motion_video,
            value: filters.igBlockReels,
            onChanged: (val) => _toggleFocusFilter(igBlockReels: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Feed Principal & Explore',
            subtitle: 'Oculta o feed infinito de postagens e sugestões da página inicial.',
            icon: Icons.dynamic_feed_outlined,
            value: filters.igBlockFeed,
            onChanged: (val) => _toggleFocusFilter(igBlockFeed: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Comentários do Instagram',
            subtitle: 'Oculta comentários sob postagens e vídeos.',
            icon: Icons.speaker_notes_off_outlined,
            value: filters.igBlockComments,
            onChanged: (val) => _toggleFocusFilter(igBlockComments: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🎵 TIKTOK FOCUS
          _buildPlatformHeader('TikTok Focus', Icons.music_note, Colors.cyanAccent),
          _buildFilterSwitch(
            title: 'Bloquear Feed de Vídeos Recomendados',
            subtitle: 'Bloqueia o fluxo infinito de vídeos curtos "Para Você" no TikTok.',
            icon: Icons.motion_photos_off_outlined,
            value: filters.ttBlockFeed,
            onChanged: (val) => _toggleFocusFilter(ttBlockFeed: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🤖 REDDIT FOCUS
          _buildPlatformHeader('Reddit Focus', Icons.forum, Colors.deepOrangeAccent),
          _buildFilterSwitch(
            title: 'Bloquear Feed Principal / Popular',
            subtitle: 'Oculta a timeline de posts infinitos no r/all e na página inicial do Reddit.',
            icon: Icons.dashboard_outlined,
            value: filters.rdBlockFeed,
            onChanged: (val) => _toggleFocusFilter(rdBlockFeed: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Seções de Comentários',
            subtitle: 'Oculta as árvores de discussão e comentários em posts do Reddit.',
            icon: Icons.speaker_notes_off_outlined,
            value: filters.rdBlockComments,
            onChanged: (val) => _toggleFocusFilter(rdBlockComments: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🐦 TWITTER / X FOCUS
          _buildPlatformHeader('X / Twitter Focus', Icons.flutter_dash, Colors.lightBlueAccent),
          _buildFilterSwitch(
            title: 'Bloquear Timeline / Feed Principal',
            subtitle: 'Oculta a timeline "Para Você" e "Seguindo" no X (Twitter).',
            icon: Icons.timeline,
            value: filters.twBlockFeed,
            onChanged: (val) => _toggleFocusFilter(twBlockFeed: val),
          ),
          _buildFilterSwitch(
            title: 'Ocultar Assuntos do Momento (Trending)',
            subtitle: 'Remove a barra lateral de tendências e notícias exploratórias.',
            icon: Icons.trending_up,
            value: filters.twBlockTrends,
            onChanged: (val) => _toggleFocusFilter(twBlockTrends: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 💼 LINKEDIN FOCUS
          _buildPlatformHeader('LinkedIn Focus', Icons.business_center, Colors.blueAccent),
          _buildFilterSwitch(
            title: 'Bloquear Feed de Notícias do LinkedIn',
            subtitle: 'Oculta a timeline de postagens para focar apenas em mensagens e perfis diretos.',
            icon: Icons.article_outlined,
            value: filters.liBlockFeed,
            onChanged: (val) => _toggleFocusFilter(liBlockFeed: val),
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🎮 LAUNCHERS & JOGOS (STEAM API + GENERIC LAUNCHERS)
          ..._buildLauncherSection(filters, isDark),
          const Divider(height: 24, color: Colors.white12),

          // 🎯 HUD FLUTUANTE NOS NAVEGADORES
          _buildPlatformHeader('HUD Flutuante nos Navegadores (Pílula)', Icons.layers_outlined, Colors.cyanAccent),
          _buildHudSlider(
            icon: Icons.opacity,
            title: 'Opacidade da Pílula (Alfa)',
            subtitle: 'Controla a transparência da pílula recolhida e do olho fechado nos navegadores.',
            value: safeAlpha,
            min: 0.15,
            max: 1.0,
            divisions: 17,
            displayValue: '${(safeAlpha * 100).round()}%',
            onChanged: (val) => setState(() => _focusFilters = _buildUpdatedFilters(hudAlpha: val)),
            onChangeEnd: (val) => _toggleFocusFilter(hudAlpha: val),
            isDark: isDark,
          ),
          _buildHudSlider(
            icon: Icons.aspect_ratio_outlined,
            title: 'Tamanho da Pílula',
            subtitle: 'Ajusta a escala da pílula e o diâmetro do olho fechado (sempre igual à altura da pílula).',
            value: safeScale,
            min: 0.70,
            max: 1.60,
            divisions: 18,
            displayValue: '${(safeScale * 100).round()}%',
            onChanged: (val) => setState(() => _focusFilters = _buildUpdatedFilters(hudScale: val)),
            onChangeEnd: (val) => _toggleFocusFilter(hudScale: val),
            isDark: isDark,
          ),
          _buildFilterSwitch(
            title: 'Ao esconder pílula, mostrar ícone de Olho arrastável',
            subtitle: 'Quando ativo, minimizar transforma a pílula em um botão circular com olho fechado arrastável do mesmo tamanho (altura) da pílula; desligado, oculta totalmente (Alt+Shift+C reexibe).',
            icon: Icons.visibility_outlined,
            value: filters.hudHideToEye,
            onChanged: (val) => _toggleFocusFilter(hudHideToEye: val),
          ),
        ],
      ),
    );
  }

  Widget _buildHudSlider({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.cyanAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      displayValue,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.tealAccent,
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: Colors.tealAccent,
                  label: displayValue,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLauncherSection(FocusFiltersDto filters, bool isDark) {
    final acLocked = _isAntiCheatActive;
    final tagSuggestions = _popularTagItems
        .where((t) => !filters.launcherBlockedTags.any(
              (b) => b.toLowerCase() == t.canonicalEn.toLowerCase(),
            ))
        .take(12)
        .map(
          (t) => _LauncherSuggestionOption(
            value: t.canonicalEn,
            label: t.displayName,
            secondaryLabel:
                t.displayName.toLowerCase() != t.canonicalEn.toLowerCase()
                    ? t.canonicalEn
                    : null,
          ),
        )
        .toList();

    final tagAutocompleteOptions = _tagAutocomplete
        .where((t) => !filters.launcherBlockedTags.any(
              (b) => b.toLowerCase() == t.canonicalEn.toLowerCase(),
            ))
        .map(
          (t) => _LauncherSuggestionOption(
            value: t.canonicalEn,
            label: t.displayName,
            secondaryLabel:
                t.displayName.toLowerCase() != t.canonicalEn.toLowerCase()
                    ? t.canonicalEn
                    : null,
          ),
        )
        .toList();

    final gameAutocompleteOptions = _gameAutocomplete
        .where((g) => !filters.launcherBlockedNames.any(
              (b) => b.toLowerCase() == g.title.toLowerCase(),
            ))
        .map(
          (g) => _LauncherSuggestionOption(
            value: g.title,
            label: g.title,
            secondaryLabel: g.appId > 0 ? '${g.source} • #${g.appId}' : g.source,
            imageUrl: g.tinyImage.isNotEmpty ? g.tinyImage : null,
          ),
        )
        .toList();

    return [
      Row(
        children: [
          Expanded(
            child: _buildPlatformHeader(
              'Launchers & Jogos (Steam API, Heroic, Epic, GOG, Lutris)',
              Icons.sports_esports_outlined,
              Colors.amberAccent,
            ),
          ),
          if (acLocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: Colors.amberAccent),
                  SizedBox(width: 4),
                  Text(
                    'Anti-Cheat Ativo (Remoção Bloqueada)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.amberAccent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      _buildFilterSwitch(
        title: 'Ativar Filtro em Launchers & Lojas de Jogos',
        subtitle:
            'Bloqueia jogos em execução, páginas de loja, guias, discussões e artworks por nome ou tag via Steam API. Adicionar é sempre livre; remover exige Anti-Cheat desativado.',
        icon: Icons.shield_outlined,
        value: filters.launcherFilterEnabled,
        onChanged: (val) {
          if (!val && acLocked) {
            _showSnack(
              'Anti-Cheat ativo: desative o Anti-Cheat para desligar o filtro de launchers.',
              false,
            );
            return;
          }
          _toggleFocusFilter(launcherFilterEnabled: val);
        },
      ),
      const SizedBox(height: 8),
      _buildTermListEditor(
        label: 'Tags Proibidas (Steam API)',
        hint: 'Buscar tag na Steam API (ex: Ação, Souls-like, Terror, FPS)...',
        icon: Icons.label_outline,
        accentColor: Colors.amberAccent,
        terms: filters.launcherBlockedTags,
        termDisplayMap: _tagDisplayMap,
        controller: _launcherTagCtrl,
        antiCheatActive: acLocked,
        quickSuggestions: tagSuggestions,
        autocompleteOptions: tagAutocompleteOptions,
        loadingAutocomplete: _loadingTagAutocomplete,
        onQueryChanged: _onLauncherTagQueryChanged,
        onAdd: (t) => _addLauncherTerm(isTag: true, rawTerm: t),
        onRemove: (t) => _removeLauncherTerm(isTag: true, term: t),
        isDark: isDark,
      ),
      const SizedBox(height: 10),
      _buildTermListEditor(
        label: 'Nomes de Jogos Proibidos',
        hint: 'Buscar jogo na Steam API (ex: Counter-Strike 2, Elden Ring)...',
        icon: Icons.videogame_asset_outlined,
        accentColor: Colors.orangeAccent,
        terms: filters.launcherBlockedNames,
        controller: _launcherNameCtrl,
        antiCheatActive: acLocked,
        autocompleteOptions: gameAutocompleteOptions,
        loadingAutocomplete: _loadingGameAutocomplete,
        onQueryChanged: _onLauncherGameQueryChanged,
        onAdd: (t) => _addLauncherTerm(isTag: false, rawTerm: t),
        onRemove: (t) => _removeLauncherTerm(isTag: false, term: t),
        isDark: isDark,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _configuringLauncherProxy ? null : () => _activateLauncherProxy(true),
            icon: _configuringLauncherProxy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.security_outlined, size: 16),
            label: const Text('Proteger Loja/Comunidade dentro da Steam/Heroic (Proxy + NSS)'),
          ),
          OutlinedButton.icon(
            onPressed: _loadingGames
                ? null
                : () {
                    if (_gamesExpanded && _installedGames.isNotEmpty) {
                      setState(() => _gamesExpanded = false);
                    } else {
                      _refreshInstalledGames();
                    }
                  },
            icon: _loadingGames
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_gamesExpanded ? Icons.expand_less : Icons.search, size: 16),
            label: Text(
              _gamesExpanded
                  ? 'Ocultar Jogos Detectados (${_installedGames.length})'
                  : 'Consultar Jogos dos Launchers (Steam API)',
            ),
          ),
        ],
      ),
      if (_gamesExpanded) ...[
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: _loadingGames
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : (_installedGames.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Nenhum jogo instalado detectado nos launchers locais (Steam, Heroic, Lutris, Bottles).',
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: _installedGames.length,
                      separatorBuilder: (_, _) => const Divider(height: 10, color: Colors.white10),
                      itemBuilder: (_, idx) {
                        final g = _installedGames[idx];
                        final tags = {...g.tags, ...g.genres}.take(6).toList();
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${g.title} • ${g.launcher}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  if (tags.isNotEmpty)
                                    Text(
                                      tags.join(', '),
                                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _addLauncherTerm(isTag: false, rawTerm: g.title),
                              child: const Text('+ Bloquear Jogo', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        );
                      },
                    )),
        ),
      ],
    ];
  }

  Widget _buildTermListEditor({
    required String label,
    required String hint,
    required IconData icon,
    required Color accentColor,
    required List<String> terms,
    required TextEditingController controller,
    required bool antiCheatActive,
    required ValueChanged<String> onAdd,
    required ValueChanged<String> onRemove,
    required bool isDark,
    Map<String, String> termDisplayMap = const {},
    List<_LauncherSuggestionOption> quickSuggestions = const [],
    List<_LauncherSuggestionOption> autocompleteOptions = const [],
    bool loadingAutocomplete = false,
    ValueChanged<String>? onQueryChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: loadingAutocomplete
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: onQueryChanged,
                  onSubmitted: onAdd,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => onAdd(controller.text),
                child: const Text('Adicionar'),
              ),
            ],
          ),
          if (autocompleteOptions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 190),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.45)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: autocompleteOptions.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white10),
                itemBuilder: (_, idx) {
                  final opt = autocompleteOptions[idx];
                  return InkWell(
                    onTap: () => onAdd(opt.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Row(
                        children: [
                          if (opt.imageUrl != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                opt.imageUrl!,
                                width: 46,
                                height: 18,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(icon, size: 15, color: accentColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            Icon(icon, size: 15, color: accentColor),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              opt.label,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (opt.secondaryLabel != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              opt.secondaryLabel!,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
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
          if (terms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: terms.map((term) {
                final display = termDisplayMap[term] ?? term;
                final labelText =
                    display.toLowerCase() != term.toLowerCase() ? '$display ($term)' : display;
                return InputChip(
                  label: Text(labelText, style: const TextStyle(fontSize: 12)),
                  tooltip: display.toLowerCase() != term.toLowerCase()
                      ? 'Tag canônica Steam API: $term'
                      : null,
                  deleteIcon: Icon(
                    antiCheatActive ? Icons.lock_outline : Icons.close,
                    size: 15,
                    color: antiCheatActive ? Colors.amberAccent : null,
                  ),
                  onDeleted: () => onRemove(term),
                );
              }).toList(),
            ),
          ],
          if (quickSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Sugestões Steam API:',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: quickSuggestions.map((tag) {
                return ActionChip(
                  label: Text('+ ${tag.label}', style: const TextStyle(fontSize: 11)),
                  tooltip: tag.secondaryLabel != null
                      ? 'Envia "${tag.value}" para a Steam API'
                      : null,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onAdd(tag.value),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlatformHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: value ? Colors.tealAccent : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: Colors.tealAccent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
      ),
      color: isDark ? const Color(0xFF161922) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
