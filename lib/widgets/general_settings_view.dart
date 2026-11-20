import 'package:chronos_app/services/app_locale.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show themeModeNotifier;
import '../services/browser_extension_installer.dart';
import '../services/chronos_guard_service.dart';
import 'challenge_texts_dialog.dart';
import '../services/app_profile.dart';
import '../services/notification_service.dart';
import '../services/web_block_server.dart';
import '../src/rust/api/simple.dart';
import '../src/rust/api/youtube.dart';
import '../src/rust/api/updater.dart';
import 'youtube_custom_types_dialog.dart';
import 'holidays_card.dart';
import 'adult_filter_card.dart';
import 'tamper_log_card.dart';
import 'uninstall_dialog.dart';
import 'anti_cheat_dialog.dart';
import 'browser_protection_panel.dart';
import 'update_dialog.dart';
import '../services/app_version.dart';

class _LauncherSuggestionOption {
  final String value;
  final String label;
  final String? secondaryLabel;
  final String? imageUrl;

  const _LauncherSuggestionOption({required this.value, required this.label, this.secondaryLabel, this.imageUrl});
}

class GeneralSettingsView extends StatefulWidget {
  final VoidCallback onResetOnboarding;
  final VoidCallback onSettingsChanged;

  const GeneralSettingsView({super.key, required this.onResetOnboarding, required this.onSettingsChanged});

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  final NotificationService _notifications = NotificationService();
  List<DetectedBrowser> _browsers = [];
  Future<bool>? _dndFuture;
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
      final results = await Future.wait<dynamic>([getAntiCheatState(), getFocusFilters()]);
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
          _tagDisplayMap = {for (final e in entries) e.canonicalEn: e.displayName};
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
        final results = await searchSteamTagsAutocomplete(query: trimmed, lang: _primaryLanguage);
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
        final results = await searchSteamGamesAutocomplete(query: trimmed, lang: _primaryLanguage);
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

  /// Language of the app, the extensions and the Steam tags. Changing it rebuilds the
  /// whole app (MaterialApp keyed by locale), so this screen reloads in the new language.
  Future<void> _changePrimaryLanguage(String lang) async {
    if (_primaryLanguage == lang) return;
    setState(() => _primaryLanguage = lang);
    final res = await setPrimaryLanguage(lang: lang);
    if (!res.success) {
      _showSnack(res.message, false);
      return;
    }
    WebBlockServer.nudgeObservers();
    setAppLanguageCode(res.message.isNotEmpty ? res.message : lang);
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
      _showSnack(tr.modoNukeAtivoRemocaoDaExtensao, false);
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
        _showSnack(tr.remocaoCanceladaConcluaAVerificacaoAnti, false);
        return;
      }
    }

    final postState = await getAntiCheatState();
    if (postState.isActive) {
      _showSnack(tr.antiCheatAindaAtivoRemocaoBloqueada, false);
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: Text(tr.removerExtensaoPoliticas, style: TextStyle(color: Colors.white)),
        content: Text(
          tr.verificacaoAntiCheatConcluidaIssoRemovera,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancelar)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr.removerDeTodosOsNavegadores),
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
      SnackBar(content: Text(msg), backgroundColor: success ? Colors.teal.shade700 : Colors.redAccent.shade700),
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
    ytShowOnlyEnabled: false,
    ytShowOnlyTypes: [],
    igBlockReels: true,
    igBlockFeed: false,
    igBlockComments: false,
    ttBlockFeed: true,
    rdBlockFeed: false,
    rdBlockComments: false,
    twBlockFeed: false,
    twBlockTrends: false,
    twBlockSensitive: false,
    rdBlockNsfw: false,
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
    bool? ytShowOnlyEnabled,
    List<String>? ytShowOnlyTypes,
    bool? igBlockReels,
    bool? igBlockFeed,
    bool? igBlockComments,
    bool? ttBlockFeed,
    bool? rdBlockFeed,
    bool? rdBlockComments,
    bool? twBlockFeed,
    bool? twBlockTrends,
    bool? twBlockSensitive,
    bool? rdBlockNsfw,
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
    final nextGlobalNotifications = globalBlockNotifications ?? current.globalBlockNotifications;
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
      ytShowOnlyEnabled: ytShowOnlyEnabled ?? current.ytShowOnlyEnabled,
      ytShowOnlyTypes: ytShowOnlyTypes ?? current.ytShowOnlyTypes,

      igBlockReels: igBlockReels ?? current.igBlockReels,
      igBlockFeed: igBlockFeed ?? current.igBlockFeed,
      igBlockComments: igBlockComments ?? current.igBlockComments,

      ttBlockFeed: ttBlockFeed ?? current.ttBlockFeed,

      rdBlockFeed: rdBlockFeed ?? current.rdBlockFeed,
      rdBlockComments: rdBlockComments ?? current.rdBlockComments,

      twBlockFeed: twBlockFeed ?? current.twBlockFeed,
      twBlockTrends: twBlockTrends ?? current.twBlockTrends,
      twBlockSensitive: twBlockSensitive ?? current.twBlockSensitive,
      rdBlockNsfw: rdBlockNsfw ?? current.rdBlockNsfw,

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
    bool? ytShowOnlyEnabled,
    List<String>? ytShowOnlyTypes,
    bool? igBlockReels,
    bool? igBlockFeed,
    bool? igBlockComments,
    bool? ttBlockFeed,
    bool? rdBlockFeed,
    bool? rdBlockComments,
    bool? twBlockFeed,
    bool? twBlockTrends,
    bool? twBlockSensitive,
    bool? rdBlockNsfw,
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
      ytShowOnlyEnabled: ytShowOnlyEnabled,
      ytShowOnlyTypes: ytShowOnlyTypes,
      igBlockReels: igBlockReels,
      igBlockFeed: igBlockFeed,
      igBlockComments: igBlockComments,
      ttBlockFeed: ttBlockFeed,
      rdBlockFeed: rdBlockFeed,
      rdBlockComments: rdBlockComments,
      twBlockFeed: twBlockFeed,
      twBlockTrends: twBlockTrends,
      twBlockSensitive: twBlockSensitive,
      rdBlockNsfw: rdBlockNsfw,
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
      _showSnack(tr.filtrosAntiDistracaoSalvosComSucesso, true);
    }
  }

  bool get _isAntiCheatActive => _antiCheatState?.isActive == true;

  void _addLauncherTerm({required bool isTag, required String rawTerm}) {
    final clean = rawTerm.trim();
    if (clean.isEmpty) return;
    final current = _focusFilters ?? _defaultFocusFilters;
    final list = List<String>.from(isTag ? current.launcherBlockedTags : current.launcherBlockedNames);
    final exists = list.any((t) => t.trim().toLowerCase() == clean.toLowerCase());
    if (exists) {
      _showSnack(tr.p0JaEstaNaLista(clean), false);
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
      _showSnack(tr.antiCheatAtivoDesativeOAnti, false);
      return;
    }
    final current = _focusFilters ?? _defaultFocusFilters;
    final list = List<String>.from(isTag ? current.launcherBlockedTags : current.launcherBlockedNames)
      ..removeWhere((t) => t == term);
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
      _showSnack(tr.antiCheatAtivoDesativeOAnti2, false);
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
                decoration: BoxDecoration(color: Colors.teal.shade900, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.settings, color: Colors.tealAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.configuracoesGerais,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    tr.ajustesDeNotificacoesExtensoesLocaisModo,
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

          // 0.1 Versão e atualizações
          _buildCard(
            title: tr.versaoEAtualizacoes,
            icon: Icons.system_update_alt,
            iconColor: Colors.lightBlueAccent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isReleaseBuild
                        ? tr.chronosP0AsAtualizacoesSaoVerificadas(appVersion)
                        : tr.chronosP0BuildDeDesenvolvimentoSem(appVersion),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr.procurarAtualizacoes),
                  onPressed: () => checkAndPromptForUpdate(context, manual: true),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_forever_outlined, size: 16),
                  label: Text(tr.desinstalarChronos2),
                  onPressed: () => showUninstallDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const HolidaysCard(),
          const SizedBox(height: 16),
          const AdultFilterCard(),
          const SizedBox(height: 16),
          const TamperLogCard(),
          if (_onboardingState?.appMode == 'PARENTAL') ...[
            const SizedBox(height: 16),
            _buildAccountProtectionCard(),
          ],
          const SizedBox(height: 16),

          // 1. Notificações de Desktop
          _buildCard(
            title: tr.notificacoesDeDesktop,
            icon: Icons.notifications_active,
            iconColor: Colors.amberAccent,
            child: Column(
              children: [
                FutureBuilder<bool>(
                  future: _dndFuture ??= NotificationService.isDoNotDisturbOn(),
                  builder: (context, snap) {
                    if (snap.data != true) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.do_not_disturb_on_outlined, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr.oModoNaoPerturbeDoSistema,
                              style: TextStyle(fontSize: 12, color: Colors.amberAccent),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _dndFuture = NotificationService.isDoNotDisturbOn()),
                            child: Text(tr.verificar),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                SwitchListTile(
                  title: Text(tr.notificarInicioDeAppMonitorado),
                  subtitle: Text(
                    tr.exibeUmaNotificacaoNoDesktopAvisando,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  value: _notifications.notifyOnAppMonitored,
                  activeTrackColor: Colors.teal.shade800,
                  onChanged: (val) {
                    setState(() => _notifications.notifyOnAppMonitored = val);
                    _showSnack(
                      val ? tr.notificacaoDeAppMonitoradoAtivada : tr.notificacaoDeAppMonitoradoDesativada,
                      true,
                    );
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                SwitchListTile(
                  title: Text(tr.alertasDeTempoDeTelaRestante),
                  subtitle: Text(
                    tr.avisosAutomaticosQuandoRestarem15m5m,
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
                  title: Text(tr.avisosPeriodicosDeUsoAtivo),
                  subtitle: Text(
                    tr.lembretesEmIntervalosRegularesExA,
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
            title: tr.extensoesDosNavegadores,
            icon: Icons.extension,
            iconColor: Colors.blueAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.protegeTodosOsNavegadoresDoDispositivo,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                BrowserSetupFlowStepper(
                  hasPackages: _browsers.isNotEmpty || (_guardStatus?.isInstalled == true),
                  guardStatus: _guardStatus,
                  browsers: _browsers,
                ),
                const SizedBox(height: 14),
                Text(
                  tr.navegadoresDetectadosNoSistema,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
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
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr.extensaoRemovidaAposVerificacaoAntiCheat,
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
                        ? tr.configurandoNavegadoresGuard
                        : tr.instalarAtualizarEmTodosOsNavegadores,
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
                const Divider(height: 28),
                _buildExtensionUpdateSection(),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2.3 Filtros de Conteúdo Anti-Distração (Estilo StayFocusd)
          _buildFocusFiltersCard(),
          const SizedBox(height: 16),

          // 2.5 Proteção Permanente do Sistema (Anti-Burla & Remoção Anti-Burla)
          _buildCard(
            title: tr.protecaoPermanenteDoSistemaAntiBurla,
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user, color: Colors.tealAccent, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr.protecaoDoSistemaAtivaTrancada,
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent, fontSize: 13),
                              ),
                              SizedBox(height: 4),
                              Text(
                                tr.politicasForcadasAtivasEmChromeChromium,
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
                        label: Text(tr.reAplicarPoliticasDoSistema),
                        onPressed: () async {
                          final ok = await ChronosGuardService.applyPoliciesIfInstalled();
                          await _loadAll();
                          _showSnack(
                            ok ? tr.politicasDoSistemaVerificadasERe : tr.falhaAoReAplicarPoliticas,
                            ok,
                          );
                        },
                      ),
                      // Release: the only way out is "Desinstalar Chronos" (removes everything);
                      // removing just the extension is a dev-only tool.
                      if (ChronosProfile.isDev)
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
                        label: Text(_removingExtensions ? tr.removendo : tr.removerExtensaoVerificarAntiCheat),
                        onPressed: _removingExtensions ? null : _handleRemoveExtensionsWithAntiCheat,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    _guardStatus?.isGuardOutdated == true
                        ? tr.oChronosGuardInstaladoPossuiPoliticas
                        : tr.oChronosGuardGravaPoliticasPermanentes,
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
                              ? tr.atualizarGuardViaPolkit1Clique
                              : tr.ativarGuardViaPolkit1Clique,
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
                      if (!_extensionsRemovedByUser && ChronosProfile.isDev)
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
                          label: Text(tr.removerExtensaoVerificarAntiCheat),
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
            title: tr.modoDoAplicativoCadastro,
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
                          tr.modoAtivoP0(_onboardingState?.appMode == "PARENTAL" ? "Controle Parental" : "Auto-Controle"),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _onboardingState?.appMode == 'PARENTAL'
                              ? tr.configuradoComPinEProtecaoParental
                              : tr.focadoEmAutonomiaComprometimentoPessoalE,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    );

                    final button = OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: Text(tr.trocarModoRefazerCadastro),
                      onPressed: widget.onResetOnboarding,
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [textColumn, const SizedBox(height: 12), button],
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

          // 4. Anti-Burla & Travamento
          _buildCard(
            title: tr.antiCheatProtecaoContraBurlar,
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
                                      ? tr.modoNukeAtivoP0SRestantes(_antiCheatState?.nukeRemainingSeconds ?? 0)
                                      : tr.antiCheatAtivoDesafioStayfocusd)
                                : tr.antiCheatDesativado,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _antiCheatState?.isActive == true ? Colors.deepOrangeAccent : Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr.bloqueiaModificacoesDeRegrasAumentoDe,
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _antiCheatState?.isActive == true
                            ? Colors.deepOrange.shade800
                            : Colors.teal.shade800,
                      ),
                      icon: const Icon(Icons.security, size: 16),
                      label: Text(_antiCheatState?.isActive == true ? tr.gerenciarAntiCheat : tr.ativarAntiCheat),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: Text(tr.textosDoDesafio),
                  onPressed: _antiCheatState?.isActive == true
                      ? () => _showSnack(tr.antiBurlaAtivoOsTextosDo, false)
                      : _editChallengeTexts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Dados & Resets (dev only: in release they would reset screen time and rules)
          if (ChronosProfile.isDev)
          _buildCard(
            title: tr.gerenciamentoDeDadosLocaisOffline,
            icon: Icons.storage,
            iconColor: Colors.cyanAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.todasAsInformacoesRegrasETempos,
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.history_toggle_off, size: 16),
                      label: Text(tr.zerarConsumoDiarioDeHoje),
                      onPressed: () async {
                        final res = await resetDailyUsage();
                        _showSnack(res.message, res.success);
                        widget.onSettingsChanged();
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                      icon: const Icon(Icons.restore, size: 16),
                      label: Text(tr.reiniciarBancoDeDadosCompleto),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(tr.reiniciarBancoDeDados2),
                            content: Text(
                              tr.atencaoIssoIraApagarTodasAs,
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancelar)),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(tr.zerarTudo),
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
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.tealAccent),
            SizedBox(width: 8),
            Text(tr.instalarProtecaoPermanente),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.estaEtapaConfiguraOsArquivosDe,
                style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                tr.comoDesejaProsseguir,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
              ),
              const SizedBox(height: 10),
              Text(
                tr.opcao1CliqueEmAbrirTerminal,
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
                      tooltip: tr.copiarComando,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(tr.comandoCopiadoParaAAreaDe)));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.fechar)),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(tr.verificarStatus),
            onPressed: () async {
              await _loadAll();
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                _showSnack(
                  _guardStatus?.isFullyActive == true
                      ? tr.protecaoDoSistemaAtivaEConfirmada
                      : tr.protecaoAindaPendenteDeInstalacao,
                  _guardStatus?.isFullyActive == true,
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
            icon: const Icon(Icons.terminal, size: 16),
            label: Text(tr.abrirTerminal),
            onPressed: () async {
              final launched = await ChronosGuardService.launchInstallerInTerminal();
              if (mounted) {
                if (launched) {
                  _showSnack(tr.terminalAbertoDigiteSuaSenhaNa, true);
                } else {
                  Clipboard.setData(ClipboardData(text: cmd));
                  _showSnack(tr.naoFoiPossivelAbrirOTerminal, false);
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
        title: Row(
          children: [
            Icon(Icons.extension, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text(tr.ativarNoGoogleChrome),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr.oGoogleChromeOficialBloqueiaInjecoes,
                        style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr.passoAPassoRapido,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
              ),
              const SizedBox(height: 10),
              _buildStepItem(
                '1',
                tr.cliqueNoBotaoAbrirChromeAbaixo,
              ),
              const SizedBox(height: 8),
              _buildStepItem('2', tr.noChromeAtiveAChaveModo),
              const SizedBox(height: 8),
              _buildStepItem('3', tr.cliqueNoBotaoCarregarSemCompactacao),
              const SizedBox(height: 8),
              _buildStepItem('4', tr.pressioneCtrlVOuSelecioneA),
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
                      tooltip: tr.copiarCaminho,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: path));
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(tr.caminhoCopiadoParaAAreaDe)));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.fechar)),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: Text(tr.baixarZip),
            onPressed: () async {
              final zip = await BrowserExtensionInstaller.exportExtensionZipToDownloads();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(zip != null ? tr.arquivoSalvoEmP0(zip) : tr.erroAoGerarZipParaDownloads),
                    backgroundColor: zip != null ? Colors.teal.shade700 : Colors.red.shade800,
                  ),
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent.shade700),
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: Text(tr.abrirChrome),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              await BrowserExtensionInstaller.launchGoogleChromeWithExtensionGuide();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr.chromeAbertoCaminhoCopiadoParaA),
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
        title: Row(
          children: [
            Icon(Icons.extension, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text(tr.ativarExtensaoNoFirefox, style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.noFirefoxReleasePadraoAMozilla,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              _buildStepItem('1', tr.cliqueNoBotaoAbrirFirefoxAbaixo),
              const SizedBox(height: 8),
              _buildStepItem('2', tr.cliqueNoBotaoCarregarExtensaoTemporaria),
              const SizedBox(height: 8),
              _buildStepItem(
                '3',
                tr.selecioneOArquivoManifestJsonNa,
              ),
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
                      tooltip: tr.copiarCaminho,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: manifestPath));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(tr.caminhoDoManifestJsonCopiado)));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.fechar)),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Baixar .xpi'),
            onPressed: () async {
              final xpi = await BrowserExtensionInstaller.exportFirefoxExtensionZipToDownloads();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(xpi != null ? tr.arquivoSalvoEmP0(xpi) : tr.erroAoGerarXpiParaDownloads),
                    backgroundColor: xpi != null ? Colors.teal.shade700 : Colors.red.shade800,
                  ),
                );
              }
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: Text(tr.abrirFirefox),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: manifestPath));
              await BrowserExtensionInstaller.launchFirefoxWithExtensionGuide();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr.firefoxAbertoCaminhoCopiadoParaA),
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
          decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
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
      title: tr.aparenciaModoDeTema,
      icon: Icons.palette_outlined,
      iconColor: Colors.cyanAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.personalizeOTemaVisualDoChronos,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text(tr.modoEscuro)),
              ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined, size: 18), label: Text(tr.modoClaro)),
              ButtonSegment(
                value: 'system',
                icon: Icon(Icons.settings_brightness_outlined, size: 18),
                label: Text(tr.sistema),
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
            tr.idiomaPrincipalTagsAutocompleteSteamApi,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            tr.asTagsSaoEnviadasEmIngles,
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: kAppLanguages.any((l) => l.$1 == _primaryLanguage) ? _primaryLanguage : 'pt-BR',
            isDense: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.translate_outlined, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final (code, label) in kAppLanguages) DropdownMenuItem(value: code, child: Text(label)),
            ],
            onChanged: (val) {
              if (val != null) _changePrimaryLanguage(val);
            },
          ),
        ],
      ),
    );
  }

  /// Highest installed Chronos extension version per Chromium-family browser profile.
  static Map<String, String> _installedChromiumExtensionVersions() {
    final home = Platform.environment['HOME'] ?? '';
    final out = <String, String>{};
    final browsers = {
      'Chrome': '.config/google-chrome',
      'Chromium': '.config/chromium',
      'Brave': '.config/BraveSoftware/Brave-Browser',
    };
    for (final entry in browsers.entries) {
      final root = Directory('$home/${entry.value}');
      if (!root.existsSync()) continue;
      String? best;
      for (final profile in root.listSync().whereType<Directory>()) {
        final extDir = Directory('${profile.path}/Extensions/${ChronosGuardService.extensionId}');
        if (!extDir.existsSync()) continue;
        for (final v in extDir.listSync().whereType<Directory>()) {
          final ver = v.uri.pathSegments.where((s) => s.isNotEmpty).last.split('_').first;
          if (best == null || compareVersions(a: ver, b: best) > 0) best = ver;
        }
      }
      if (best != null) out[entry.key] = best;
    }
    return out;
  }

  /// Parental mode: a child account with admin rights can remove Chronos as root.
  Widget _buildAccountProtectionCard() {
    final st = ChronosGuardService.accountProtectionStatus();
    final ok = st.isProtected || !st.isAdmin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(ok ? Icons.verified_user : Icons.admin_panel_settings,
                  color: ok ? Colors.tealAccent : Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              Text(tr.contaDaCriancaProtegida, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 6),
            Text(
              st.isProtected
                  ? tr.contaProtegidaDescricao(st.user)
                  : st.isAdmin
                      ? tr.contaEhAdministradoraAviso(st.user)
                      : tr.contaSemAdministrador(st.user),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            if (st.isAdmin || st.isProtected)
              OutlinedButton.icon(
                icon: Icon(st.isProtected ? Icons.lock_open : Icons.lock, size: 16),
                label: Text(st.isProtected ? tr.devolverAdministrador : tr.protegerEstaConta),
                onPressed: () async {
                  final err = await ChronosGuardService.setAccountProtection(!st.isProtected);
                  _showSnack(err ?? tr.feitoValeNoProximoLogin, err == null);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Chronos add-on version installed in Firefox (newest across profiles).
  static String? _installedFirefoxExtensionVersion() {
    final home = Platform.environment['HOME'] ?? '';
    String? best;
    for (final base in [
      '$home/.mozilla/firefox',
      '$home/.config/mozilla/firefox',
      '$home/snap/firefox/common/.mozilla/firefox', // Ubuntu snap
    ]) {
      final root = Directory(base);
      if (!root.existsSync()) continue;
      for (final profile in root.listSync().whereType<Directory>()) {
        final f = File('${profile.path}/extensions.json');
        if (!f.existsSync()) continue;
        try {
          final addons = (jsonDecode(f.readAsStringSync()) as Map)['addons'] as List;
          for (final a in addons) {
            if (a is Map && a['id'] == 'chronos-focus@chronos.local') {
              final v = a['version']?.toString() ?? '';
              if (v.isNotEmpty && (best == null || compareVersions(a: v, b: best) > 0)) best = v;
            }
          }
        } catch (_) {}
      }
    }
    return best;
  }

  /// Browser extensions follow app updates automatically (toggle) or on demand.
  /// Own challenge texts (one per block, separated by a blank line). They are drawn
  /// together with the built-in texts whenever the challenge mode is activated.
  Future<void> _editChallengeTexts() async {
    final msg = await showDialog<String>(context: context, builder: (_) => const ChallengeTextsDialog());
    if (msg != null && msg.isNotEmpty) _showSnack(msg, true);
  }

  /// Version / auto-update part of the browser extensions card.
  Widget _buildExtensionUpdateSection() {
    final status = getExtensionUpdateStatus();
    final installed = _installedChromiumExtensionVersions();
    // Live version reported by the extension itself (< 2 min old) beats profile files.
    const names = {
      'chrome': 'Chrome', 'chromium': 'Chromium', 'brave': 'Brave', 'edge': 'Edge',
      'opera': 'Opera', 'vivaldi': 'Vivaldi', 'firefox': 'Firefox',
    };
    try {
      for (final r in getExtensionReports()) {
        if (r.ageSeconds.toInt() > 120 || r.version.isEmpty) continue;
        installed[names[r.browser] ?? r.browser] = r.version;
      }
    } catch (_) {}
    final firefox = installed.remove('Firefox') ?? _installedFirefoxExtensionVersion();
    String line(String browser, String version, String latest) {
      final upToDate = latest.isEmpty || compareVersions(a: version, b: latest) >= 0;
      return '$browser: $version ${upToDate ? tr.extVersaoAtualizada : tr.extVersaoPendente(latest)}';
    }
    final lines = [
      for (final e in installed.entries) line(e.key, e.value, status.latestVersion),
      // Firefox only installs Mozilla-signed versions: compare with the signed one.
      if (firefox != null)
        status.firefoxLatestVersion.isEmpty || compareVersions(a: status.firefoxLatestVersion, b: firefox) <= 0
            ? (compareVersions(a: firefox, b: status.latestVersion) >= 0
                ? line('Firefox', firefox, '')
                : 'Firefox: $firefox ${tr.extFirefoxPrecisaAssinar(status.latestVersion)}')
            : line('Firefox', firefox, status.firefoxLatestVersion),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.atualizacoesDaExtensao, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr.atualizarExtensoesAutomaticamente, style: TextStyle(fontSize: 14)),
          subtitle: Text(
            tr.quandoOChronosForAtualizadoOs,
            style: TextStyle(fontSize: 12),
          ),
          value: status.autoUpdate,
          onChanged: (v) async {
            await setExtensionAutoUpdate(enabled: v);
            if (mounted) setState(() {});
          },
        ),
        Text(
          [
            tr.extVersaoDisponivel(status.latestVersion.isEmpty ? '—' : status.latestVersion),
            ...lines,
          ].join('\n'),
          style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.system_update, size: 16),
          label: Text(tr.atualizarExtensoesAgora),
          onPressed: () async {
            await requestExtensionUpdateNow();
            _showSnack(tr.pedidoEnviadoOChromeInstalaA, true);
            Future.delayed(const Duration(seconds: 15), () {
              if (mounted) setState(() {});
            });
          },
        ),
      ],
    );
  }

  /// YouTube "Mostrar apenas": only videos of the chosen types appear on the home feed
  /// and related list; disallowed Shorts are skipped. Search still shows everything.
  Widget _buildYoutubeShowOnlySection(FocusFiltersDto filters) {
    final types = getYoutubeContentTypes();
    final selected = filters.ytShowOnlyTypes.map((t) => t.toLowerCase()).toSet();

    void setTypes(Set<String> next) {
      final list = next.toList()..sort();
      _toggleFocusFilter(ytShowOnlyTypes: list, ytShowOnlyEnabled: list.isEmpty ? false : filters.ytShowOnlyEnabled);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterSwitch(
            title: tr.mostrarApenasVideosDestesTipos,
            subtitle: selected.isEmpty ? tr.escolhaAoMenosUmTipoAbaixo : tr.aHomeEOsRelacionadosSo,
            icon: Icons.filter_alt_outlined,
            value: filters.ytShowOnlyEnabled,
            onChanged: (val) {
              if (val && selected.isEmpty) {
                _showSnack(tr.escolhaAoMenosUmTipoAntes, false);
                return;
              }
              _toggleFocusFilter(ytShowOnlyEnabled: val);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final t in types)
                  FilterChip(
                    label: Text(t.label),
                    selected: selected.contains(t.id),
                    onSelected: (on) {
                      final next = {...selected};
                      on ? next.add(t.id) : next.remove(t.id);
                      setTypes(next);
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(tr.importarDaListaBranca),
                  onPressed: () async {
                    final imported = <String>{};
                    for (final g in await getAllWhitelistGroups()) {
                      try {
                        final decoded = jsonDecode(g.items);
                        if (decoded is Map && decoded['yt_types'] is List) {
                          for (final t in decoded['yt_types']) {
                            final id = t is String ? t : (t is Map ? (t['type'] ?? '').toString() : '');
                            if (id.isNotEmpty) imported.add(id.toLowerCase());
                          }
                        }
                      } catch (_) {}
                    }
                    if (imported.isEmpty) {
                      _showSnack(tr.nenhumTipoDoYoutubeNaLista, false);
                      return;
                    }
                    setTypes({...selected, ...imported});
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text(tr.tiposPorCanalPalavra),
                  onPressed: () async {
                    await showDialog<void>(context: context, builder: (_) => const YoutubeCustomTypesDialog());
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
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
      title: tr.filtrosDeConteudoAntiDistracaoPor,
      icon: Icons.filter_alt_outlined,
      iconColor: Colors.deepPurpleAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.configureFiltrosDeCssEHtml,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // 🌐 DETOX GLOBAL (PRIMEIRO)
          _buildPlatformSection(
            id: 'global',
            title: tr.detoxGlobalTodosOsSites,
            icon: Icons.public,
            color: Colors.tealAccent,
            values: [filters.globalGrayscale, filters.globalBlockNotifications],
            onAll: (v) => _toggleFocusFilter(globalGrayscale: v, globalBlockNotifications: v),
            children: [
              _buildFilterSwitch(
                title: tr.modoPretoEBrancoGrayscaleDetox,
                subtitle: tr.aplicaEscalaDeCinzaEmTodas,
                icon: Icons.monochrome_photos,
                value: filters.globalGrayscale,
                onChanged: (val) => _toggleFocusFilter(globalGrayscale: val),
              ),
              _buildFilterSwitch(
                title: tr.bloquearNotificacoesEBadges,
                subtitle: tr.removeSinosVermelhosEAlertasNumericos,
                icon: Icons.notifications_off_outlined,
                value: filters.globalBlockNotifications,
                onChanged: (val) => _toggleFocusFilter(globalBlockNotifications: val),
              ),
            ],
          ),

          // 🔴 YOUTUBE FOCUS
          _buildPlatformSection(
            id: 'youtube',
            title: tr.youtubeFocus,
            icon: Icons.play_circle_filled,
            color: Colors.redAccent,
            values: [filters.ytBlockShorts, filters.ytEducationalMode, filters.ytBlockSidebar, filters.ytBlockComments],
            onAll: (v) => _toggleFocusFilter(
              ytBlockShorts: v,
              ytEducationalMode: v,
              ytBlockSidebar: v,
              ytBlockComments: v,
            ),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearYoutubeShorts,
                subtitle: tr.ocultaCarrosseisDeShortsNaHome,
                icon: Icons.movie_filter_outlined,
                value: filters.ytBlockShorts,
                onChanged: (val) => _toggleFocusFilter(ytBlockShorts: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarFeedDaHome,
                subtitle: tr.ocultaTodasAsRecomendacoesAlgoritmicasDa,
                icon: Icons.school_outlined,
                value: filters.ytEducationalMode,
                onChanged: (val) => _toggleFocusFilter(ytEducationalMode: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarVideosRelacionadosBarraLateral,
                subtitle: tr.removeSugestoesDeVideosAoLado,
                icon: Icons.view_sidebar_outlined,
                value: filters.ytBlockSidebar,
                onChanged: (val) => _toggleFocusFilter(ytBlockSidebar: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarComentariosDoYoutube,
                subtitle: tr.ocultaTodaASecaoDeComentarios,
                icon: Icons.speaker_notes_off_outlined,
                value: filters.ytBlockComments,
                onChanged: (val) => _toggleFocusFilter(ytBlockComments: val),
              ),
              _buildYoutubeShowOnlySection(filters),
            ],
          ),

          // 📸 INSTAGRAM FOCUS
          _buildPlatformSection(
            id: 'instagram',
            title: tr.instagramFocus,
            icon: Icons.camera_alt,
            color: Colors.pinkAccent,
            values: [filters.igBlockReels, filters.igBlockFeed, filters.igBlockComments],
            onAll: (v) => _toggleFocusFilter(igBlockReels: v, igBlockFeed: v, igBlockComments: v),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearInstagramReels,
                subtitle: tr.removeAAbaEOCarrossel,
                icon: Icons.slow_motion_video,
                value: filters.igBlockReels,
                onChanged: (val) => _toggleFocusFilter(igBlockReels: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarFeedPrincipalExplore,
                subtitle: tr.ocultaOFeedInfinitoDePostagens,
                icon: Icons.dynamic_feed_outlined,
                value: filters.igBlockFeed,
                onChanged: (val) => _toggleFocusFilter(igBlockFeed: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarComentariosDoInstagram,
                subtitle: tr.ocultaComentariosSobPostagensEVideos,
                icon: Icons.speaker_notes_off_outlined,
                value: filters.igBlockComments,
                onChanged: (val) => _toggleFocusFilter(igBlockComments: val),
              ),
            ],
          ),

          // 🎵 TIKTOK FOCUS
          _buildPlatformSection(
            id: 'tiktok',
            title: tr.tiktokFocus,
            icon: Icons.music_note,
            color: Colors.cyanAccent,
            values: [filters.ttBlockFeed],
            onAll: (v) => _toggleFocusFilter(ttBlockFeed: v),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearFeedDeVideosRecomendados,
                subtitle: tr.bloqueiaOFluxoInfinitoDeVideos,
                icon: Icons.motion_photos_off_outlined,
                value: filters.ttBlockFeed,
                onChanged: (val) => _toggleFocusFilter(ttBlockFeed: val),
              ),
            ],
          ),

          // 🤖 REDDIT FOCUS
          _buildPlatformSection(
            id: 'reddit',
            title: tr.redditFocus,
            icon: Icons.forum,
            color: Colors.deepOrangeAccent,
            values: [filters.rdBlockFeed, filters.rdBlockComments, filters.rdBlockNsfw],
            onAll: (v) => _toggleFocusFilter(rdBlockFeed: v, rdBlockComments: v, rdBlockNsfw: v),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearFeedPrincipalPopular,
                subtitle: tr.ocultaATimelineDePostsInfinitos,
                icon: Icons.dashboard_outlined,
                value: filters.rdBlockFeed,
                onChanged: (val) => _toggleFocusFilter(rdBlockFeed: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarSecoesDeComentarios,
                subtitle: tr.ocultaAsArvoresDeDiscussaoE,
                icon: Icons.speaker_notes_off_outlined,
                value: filters.rdBlockComments,
                onChanged: (val) => _toggleFocusFilter(rdBlockComments: val),
              ),
              _buildFilterSwitch(
                title: tr.bloquearConteudo18Nsfw,
                subtitle: tr.escondePostsNsfwNosFeedsE,
                icon: Icons.no_adult_content,
                value: filters.rdBlockNsfw,
                onChanged: (val) => _toggleFocusFilter(rdBlockNsfw: val),
              ),
            ],
          ),

          // 🐦 TWITTER / X FOCUS
          _buildPlatformSection(
            id: 'twitter',
            title: tr.xTwitterFocus,
            icon: Icons.flutter_dash,
            color: Colors.lightBlueAccent,
            values: [filters.twBlockFeed, filters.twBlockTrends, filters.twBlockSensitive],
            onAll: (v) => _toggleFocusFilter(twBlockFeed: v, twBlockTrends: v, twBlockSensitive: v),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearTimelineFeedPrincipal,
                subtitle: tr.ocultaATimelineParaVoceE,
                icon: Icons.timeline,
                value: filters.twBlockFeed,
                onChanged: (val) => _toggleFocusFilter(twBlockFeed: val),
              ),
              _buildFilterSwitch(
                title: tr.ocultarAssuntosDoMomentoTrending,
                subtitle: tr.removeABarraLateralDeTendencias,
                icon: Icons.trending_up,
                value: filters.twBlockTrends,
                onChanged: (val) => _toggleFocusFilter(twBlockTrends: val),
              ),
              _buildFilterSwitch(
                title: tr.bloquearConteudo18Sensivel,
                subtitle: tr.escondePostsComMidiaSensivelE,
                icon: Icons.no_adult_content,
                value: filters.twBlockSensitive,
                onChanged: (val) => _toggleFocusFilter(twBlockSensitive: val),
              ),
            ],
          ),

          // 💼 LINKEDIN FOCUS
          _buildPlatformSection(
            id: 'linkedin',
            title: tr.linkedinFocus,
            icon: Icons.business_center,
            color: Colors.blueAccent,
            values: [filters.liBlockFeed],
            onAll: (v) => _toggleFocusFilter(liBlockFeed: v),
            children: [
              _buildFilterSwitch(
                title: tr.bloquearFeedDeNoticiasDoLinkedin,
                subtitle: tr.ocultaATimelineDePostagensPara,
                icon: Icons.article_outlined,
                value: filters.liBlockFeed,
                onChanged: (val) => _toggleFocusFilter(liBlockFeed: val),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white12),

          // 🎮 LAUNCHERS & JOGOS (STEAM API + GENERIC LAUNCHERS)
          ..._buildLauncherSection(filters, isDark),
          const Divider(height: 24, color: Colors.white12),

          // 🎯 HUD FLUTUANTE NOS NAVEGADORES
          _buildPlatformHeader(tr.hudFlutuanteNosNavegadoresPilula, Icons.layers_outlined, Colors.cyanAccent),
          _buildHudSlider(
            icon: Icons.opacity,
            title: tr.opacidadeDaPilulaAlfa,
            subtitle: tr.controlaATransparenciaDaPilulaRecolhida,
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
            title: tr.tamanhoDaPilula,
            subtitle: tr.ajustaAEscalaDaPilulaE,
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
            title: tr.aoEsconderPilulaMostrarIconeDe,
            subtitle: tr.quandoAtivoMinimizarTransformaAPilula,
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
                    ),
                  ],
                ),
                Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
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
        .where((t) => !filters.launcherBlockedTags.any((b) => b.toLowerCase() == t.canonicalEn.toLowerCase()))
        .take(12)
        .map(
          (t) => _LauncherSuggestionOption(
            value: t.canonicalEn,
            label: t.displayName,
            secondaryLabel: t.displayName.toLowerCase() != t.canonicalEn.toLowerCase() ? t.canonicalEn : null,
          ),
        )
        .toList();

    final tagAutocompleteOptions = _tagAutocomplete
        .where((t) => !filters.launcherBlockedTags.any((b) => b.toLowerCase() == t.canonicalEn.toLowerCase()))
        .map(
          (t) => _LauncherSuggestionOption(
            value: t.canonicalEn,
            label: t.displayName,
            secondaryLabel: t.displayName.toLowerCase() != t.canonicalEn.toLowerCase() ? t.canonicalEn : null,
          ),
        )
        .toList();

    final gameAutocompleteOptions = _gameAutocomplete
        .where((g) => !filters.launcherBlockedNames.any((b) => b.toLowerCase() == g.title.toLowerCase()))
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
              tr.launchersJogosSteamApiHeroicEpic,
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: Colors.amberAccent),
                  SizedBox(width: 4),
                  Text(
                    tr.antiCheatAtivoRemocaoBloqueada,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.amberAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
      _buildFilterSwitch(
        title: tr.ativarFiltroEmLaunchersLojasDe,
        subtitle: tr.bloqueiaJogosEmExecucaoPaginasDe,
        icon: Icons.shield_outlined,
        value: filters.launcherFilterEnabled,
        onChanged: (val) {
          if (!val && acLocked) {
            _showSnack(tr.antiCheatAtivoDesativeOAnti3, false);
            return;
          }
          _toggleFocusFilter(launcherFilterEnabled: val);
        },
      ),
      const SizedBox(height: 8),
      _buildTermListEditor(
        label: tr.tagsProibidasSteamApi,
        hint: tr.buscarTagNaSteamApiEx,
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
        label: tr.nomesDeJogosProibidos,
        hint: tr.buscarJogoNaSteamApiEx,
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
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.security_outlined, size: 16),
            label: Text(tr.protegerLojaComunidadeDentroDaSteam),
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
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_gamesExpanded ? Icons.expand_less : Icons.search, size: 16),
            label: Text(
              _gamesExpanded
                  ? tr.ocultarJogosDetectadosP0(_installedGames.length)
                  : tr.consultarJogosDosLaunchersSteamApi,
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
                    ? Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          tr.nenhumJogoInstaladoDetectadoNosLaunchers,
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
                                child: Text(tr.bloquearJogo, style: TextStyle(fontSize: 11)),
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
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onChanged: onQueryChanged,
                  onSubmitted: onAdd,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: () => onAdd(controller.text), child: Text(tr.adicionar)),
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
                              style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54),
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
                final labelText = display.toLowerCase() != term.toLowerCase() ? '$display ($term)' : display;
                return InputChip(
                  label: Text(labelText, style: const TextStyle(fontSize: 12)),
                  tooltip: display.toLowerCase() != term.toLowerCase() ? tr.tagCanonicaSteamApiP0(term) : null,
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
              tr.sugestoesSteamApi,
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: quickSuggestions.map((tag) {
                return ActionChip(
                  label: Text('+ ${tag.label}', style: const TextStyle(fontSize: 11)),
                  tooltip: tag.secondaryLabel != null ? tr.enviaP0ParaASteamApi(tag.value) : null,
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

  final Set<String> _expandedFilterSections = <String>{};

  /// Collapsible platform section: the title row has a switch that turns every filter
  /// of the platform on/off (on only when all are on) and a chevron to show the list.
  Widget _buildPlatformSection({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    required List<bool> values,
    required ValueChanged<bool> onAll,
    required List<Widget> children,
  }) {
    final expanded = _expandedFilterSections.contains(id);
    final onCount = values.where((v) => v).length;
    final allOn = values.isNotEmpty && onCount == values.length;
    void toggleExpanded() => setState(() {
          if (!_expandedFilterSections.remove(id)) _expandedFilterSections.add(id);
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
                  ),
                ),
                Text('$onCount/${values.length}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(width: 6),
                Tooltip(
                  message: allOn ? tr.desativarTodos : tr.ativarTodos,
                  child: Switch(value: allOn, onChanged: onAll),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white60),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                )
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 12, color: Colors.white12),
      ],
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
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
                Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, activeThumbColor: Colors.tealAccent, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Color iconColor, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 1),
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
