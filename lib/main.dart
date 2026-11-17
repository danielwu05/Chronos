// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/legacy.dart';
import 'package:chronos_app/screens/onboarding_screen.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_daemon_service.dart';
import 'package:chronos_app/services/notification_service.dart';
import 'package:chronos_app/services/web_block_server.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/src/rust/frb_generated.dart';
import 'package:chronos_app/widgets/anti_cheat_dialog.dart';
import 'package:chronos_app/widgets/analytics_view.dart';
import 'package:chronos_app/widgets/db_test_panel.dart';
import 'package:chronos_app/widgets/focus_overlay.dart';
import 'package:chronos_app/widgets/quarantine_view.dart';
import 'package:chronos_app/widgets/rules_view.dart';
import 'package:chronos_app/widgets/general_settings_view.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

String? resolveBundledRustLibraryPath({
  String? executablePath,
  bool? isLinuxOverride,
}) {
  final isLinux = isLinuxOverride ?? Platform.isLinux;
  if (!isLinux) return null;
  final exePath = executablePath ?? Platform.resolvedExecutable;
  final exeDir = File(exePath).parent.path;
  final bundledPath = '$exeDir/lib/librust_lib_chronos_app.so';
  if (File(bundledPath).existsSync()) {
    return bundledPath;
  }
  return null;
}

ExternalLibrary? _resolveBundledRustLibrary() {
  final path = resolveBundledRustLibraryPath();
  return path == null ? null : ExternalLibrary.open(path);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await RustLib.init(externalLibrary: _resolveBundledRustLibrary());

  const windowOptions = WindowOptions(
    size: Size(1100, 760),
    minimumSize: Size(260, 220),
    center: true,
    title: 'Chronos - Anti-Cheat & Strict Focus Engine',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final dir = await getApplicationDocumentsDirectory();
  await ChronosDaemonService.ensureBackgroundDaemonRunning(dbPath: '${dir.path}/chronos.db');
  final dbOk = await setupDatabase(appDataDir: dir.path);
  await WebBlockServer.start();
  if (!BrowserExtensionInstaller.hasUserRemovedExtensionFlag()) {
    unawaited(BrowserExtensionInstaller.installAll());
  }

  runApp(ChronosApp(isDbReady: dbOk));
}

class ChronosApp extends StatefulWidget {
  final bool isDbReady;
  const ChronosApp({super.key, required this.isDbReady});

  @override
  State<ChronosApp> createState() => _ChronosAppState();
}

class _ChronosAppState extends State<ChronosApp> {
  bool _loading = true;
  bool _isOnboarded = false;
  OnboardingStateDto? _onboardingState;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _checkOnboarding();
  }

  Future<void> _loadTheme() async {
    try {
      final mode = await getThemeMode();
      if (mode == 'light') {
        themeModeNotifier.value = ThemeMode.light;
      } else if (mode == 'system') {
        themeModeNotifier.value = ThemeMode.system;
      } else {
        themeModeNotifier.value = ThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> _checkOnboarding() async {
    if (!widget.isDbReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final s = await getOnboardingState();
      if (mounted) {
        setState(() {
          _onboardingState = s;
          _isOnboarded = s.isOnboarded;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCompleted() {
    _checkOnboarding();
  }

  void _resetToOnboarding() async {
    await resetOnboardingState();
    if (mounted) {
      setState(() {
        _isOnboarded = false;
      });
      _checkOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Chronos Focus Engine',
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
              ),
              child: child!,
            );
          },
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.teal,
            scaffoldBackgroundColor: const Color(0xFFF6F8FA),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
            ),
            dividerColor: const Color(0xFFE2E8F0),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.teal,
            scaffoldBackgroundColor: const Color(0xFF121417),
            cardTheme: CardThemeData(
              color: const Color(0xFF1B1E23),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFF2D3748), width: 0.8),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1B1E23),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            dividerColor: const Color(0xFF2D3748),
          ),
          home: _loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : (!_isOnboarded
                  ? OnboardingScreen(onOnboardingCompleted: _onCompleted)
                  : HomeScreen(
                      isDbReady: widget.isDbReady,
                      onboardingState: _onboardingState,
                      onResetOnboarding: _resetToOnboarding,
                    )),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isDbReady;
  final OnboardingStateDto? onboardingState;
  final VoidCallback onResetOnboarding;

  const HomeScreen({
    super.key,
    required this.isDbReady,
    required this.onboardingState,
    required this.onResetOnboarding,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  String _activeEntityId = 'auto'; // 100% Automático via engine::tick_auto()
  StreamSubscription<LiveEngineTick>? _trackingSubscription;
  final ValueNotifier<LiveEngineTick?> _tickNotifier = ValueNotifier<LiveEngineTick?>(null);
  final ValueNotifier<bool> _isStreamErrorNotifier = ValueNotifier<bool>(false);
  bool _isOverlayActive = false;
  AntiCheatStateDto? _antiCheatState;
  LiveEngineTick? _latestTick;
  Timer? _nukeTicker;
  Timer? _extensionRepairTimer;
  bool _isReconnectingStream = false;

  void _notifySiteBlockedInBrowser(String entityId) {
    // A substituição da aba é realizada in-place pela extensão do Chronos no navegador atual.
  }

  @override
  void initState() {
    super.initState();
    _initHomeAndExtensions();
    _startStream();

    _nukeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_antiCheatState != null && _antiCheatState!.mode == 'NUKE' && _antiCheatState!.nukeRemainingSeconds > 0) {
        setState(() {
          final rem = _antiCheatState!.nukeRemainingSeconds - 1;
          _antiCheatState = AntiCheatStateDto(
            isActive: rem > 0,
            mode: rem > 0 ? 'NUKE' : 'OFF',
            nukeRemainingSeconds: rem > 0 ? rem : 0,
            challengeText: _stateTextOrEmpty(_antiCheatState!.challengeText),
          );
        });
      }
    });

    // Auto-reparo e varredura contínua de todos os navegadores instalados
    _extensionRepairTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final ac = _antiCheatState ?? await getAntiCheatState();
        final sites = await getAllSiteRulesStatus();
        final hasActiveRules = sites.any((s) => s.dailyQuotaSeconds > 0 || s.isBlocked);
        await BrowserExtensionInstaller.verifyAndAutoRepairExtensions(
          hasActiveSiteRules: hasActiveRules,
          isAntiCheatActive: ac.isActive,
        );
      } catch (_) {}
    });
  }

  String _stateTextOrEmpty(String text) => text;

  Future<void> _initHomeAndExtensions() async {
    await _refreshAntiCheat();
    final isAcActive = _antiCheatState?.isActive ?? false;
    if (isAcActive || !BrowserExtensionInstaller.hasUserRemovedExtensionFlag()) {
      await BrowserExtensionInstaller.installAll(
        isAntiCheatActive: isAcActive,
        forceMandatory: isAcActive,
      );
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isDbReady && widget.isDbReady) {
      _startStream();
    }
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    _trackingSubscription = null;
    _tickNotifier.dispose();
    _isStreamErrorNotifier.dispose();
    _nukeTicker?.cancel();
    _extensionRepairTimer?.cancel();
    if (_isOverlayActive) {
      _enforceWindowOverlay(false);
    }
    super.dispose();
  }

  Future<void> _refreshAntiCheat() async {
    try {
      final s = await getAntiCheatState();
      if (mounted) {
        setState(() {
          _antiCheatState = s;
        });
      }
    } catch (_) {}
  }

  void _openAntiCheatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AntiCheatDialog(
        onStateChanged: () {
          _refreshAntiCheat();
          _startStream();
        },
      ),
    );
  }

  void _startStream() {
    if (!widget.isDbReady) return;

    // Cancela qualquer assinatura ativa com segurança antes de iniciar uma nova
    _trackingSubscription?.cancel();
    _trackingSubscription = null;

    try {
      final stream = startTrackingStream(entityId: _activeEntityId);
      _trackingSubscription = stream.listen(
        (tick) {
          _latestTick = tick;
          _tickNotifier.value = tick;
          if (_isStreamErrorNotifier.value) {
            _isStreamErrorNotifier.value = false;
          }

          // Efeitos colaterais (overlay e bloqueio de abas) acionados no momento do tick
          if (mounted) {
            final isBlocked = tick.isBlocked;
            final isActiveNow = tick.isActiveNow;
            final isSite = tick.targetType == 'SITE';

            if (!isSite) {
              _enforceWindowOverlay(isBlocked && isActiveNow);
            } else {
              _enforceWindowOverlay(false);
              if (isBlocked && isActiveNow) {
                _notifySiteBlockedInBrowser(tick.entityId);
              }
            }
          }

          // Notificações de sessões ativas
          if (tick.activeSessionsJson.isNotEmpty) {
            try {
              final parsed = jsonDecode(tick.activeSessionsJson);
              if (parsed is List) {
                for (final s in parsed) {
                  if (s is Map) {
                    NotificationService().checkSession(Map<String, dynamic>.from(s));
                  }
                }
              }
            } catch (_) {}
          }
        },
        onError: (err) {
          _isStreamErrorNotifier.value = true;
          _scheduleStreamReconnect();
        },
        onDone: () {
          _scheduleStreamReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _isStreamErrorNotifier.value = true;
      _scheduleStreamReconnect();
    }

    _refreshAntiCheat();
  }

  void _scheduleStreamReconnect() {
    if (_isReconnectingStream || !mounted) return;
    _isReconnectingStream = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _isReconnectingStream = false;
        _startStream();
      }
    });
  }

  void _switchEntity(String newEntityId) {
    if (_activeEntityId != newEntityId) {
      setState(() {
        _activeEntityId = newEntityId;
      });
      _startStream();
    }
  }

  void _enforceWindowOverlay(bool shouldBlockNow) async {
    if (shouldBlockNow == _isOverlayActive) return;
    _isOverlayActive = shouldBlockNow;
    try {
      if (shouldBlockNow) {
        await windowManager.focus();
      }
    } catch (_) {}
  }

  void _showSnack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.teal.shade700 : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleQuickResetDb() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Reiniciar Banco de Dados?'),
          ],
        ),
        content: const Text(
          'Deseja resetar completamente o SQLite? Intervalos serão limpos, '
          'a catraca será destravada e a configuração inicial será reiniciada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reiniciar Tudo'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final res = await resetDatabaseFull();
    _showSnack(res.message, res.success);
    widget.onResetOnboarding();
  }

  Future<void> _handleQuickResetDaily() async {
    final res = await resetDailyUsage();
    _showSnack(res.message, res.success);
    _startStream();
  }

  Future<void> _handleQuickUnlockRatchet() async {
    final res = await debugUnlockRatchet(entityId: _activeEntityId);
    _showSnack(res.message, res.success);
    _startStream();
  }

  Future<void> _handleQuickRefillTokens() async {
    final res = await refillEmergencyTokens();
    _showSnack(res.message, res.success);
    _startStream();
  }

  Widget _buildModeBadge() {
    final mode = widget.onboardingState?.appMode ?? 'SELF_CONTROL';
    final role = widget.onboardingState?.deviceRole ?? 'NONE';

    if (mode == 'PARENTAL') {
      final isParent = role == 'PARENT';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.purple.shade900.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purpleAccent, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isParent ? Icons.admin_panel_settings : Icons.child_care,
              size: 14,
              color: Colors.purpleAccent,
            ),
            const SizedBox(width: 6),
            Text(
              isParent ? 'Parental (Pai)' : 'Parental (Filho)',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.purpleAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.teal.shade900.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.tealAccent, width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 14, color: Colors.tealAccent),
            SizedBox(width: 6),
            Text(
              'Auto-Controle',
              style: TextStyle(
                fontSize: 11,
                color: Colors.tealAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFocusBadge(LiveEngineTick? tick) {
    final hasActiveDistraction = tick != null && tick.isActiveNow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: hasActiveDistraction
            ? Colors.teal.shade900.withValues(alpha: 0.4)
            : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasActiveDistraction ? Colors.tealAccent : Colors.white24,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt,
            size: 14,
            color: hasActiveDistraction ? Colors.tealAccent : Colors.white54,
          ),
          const SizedBox(width: 4),
          Text(
            tick != null
                ? (hasActiveDistraction ? 'Foco: ${tick.displayName}' : 'Auto-Detecção Ativa')
                : 'Detecção Automática',
            style: TextStyle(
              fontSize: 11,
              color: hasActiveDistraction ? Colors.tealAccent : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntiCheatButton({bool isCompact = false}) {
    final state = _antiCheatState;
    final isActive = state?.isActive ?? false;
    final isNuke = state?.mode == 'NUKE';

    Color bg = const Color(0xFF1E2430);
    Color border = Colors.white24;
    Color textColor = Colors.white70;
    IconData icon = Icons.shield_outlined;
    String label = 'Anti-Cheat: OFF';

    if (isActive) {
      if (isNuke) {
        bg = Colors.deepOrange.shade900.withValues(alpha: 0.4);
        border = Colors.deepOrangeAccent;
        textColor = Colors.deepOrangeAccent;
        icon = Icons.warning_amber_rounded;
        final remSec = state!.nukeRemainingSeconds;
        final d = remSec ~/ 86400;
        final h = (remSec % 86400) ~/ 3600;
        final m = (remSec % 3600) ~/ 60;
        final s = remSec % 60;
        label = d > 0
            ? 'Nuke: ${d}d ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
            : 'Nuke: ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      } else {
        bg = Colors.amber.shade900.withValues(alpha: 0.35);
        border = Colors.amberAccent;
        textColor = Colors.amberAccent;
        icon = Icons.lock;
        label = 'Anti-Cheat Ativo';
      }
    }

    if (isCompact) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, size: 20, color: textColor),
        onPressed: _openAntiCheatDialog,
      );
    }

    return InkWell(
      onTap: _openAntiCheatDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'install_extensions':
        BrowserExtensionInstaller.installAll(
          isAntiCheatActive: _antiCheatState?.isActive ?? false,
          forceMandatory: true,
        ).then((res) => _showSnack(res.message, res.success));
        break;
      case 'reset_full':
        _handleQuickResetDb();
        break;
      case 'reset_daily':
        _handleQuickResetDaily();
        break;
      case 'unlock_ratchet':
        _handleQuickUnlockRatchet();
        break;
      case 'refill_tokens':
        _handleQuickRefillTokens();
        break;
      case 'debug_disable_anticheat':
        debugDisableAntiCheat().then((res) {
          _showSnack(res.message, res.success);
          notifyAntiCheatStateChanged();
          _refreshAntiCheat();
          _startStream();
        });
        break;
      case 'reset_onboarding':
        widget.onResetOnboarding();
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems({bool isHalfScreen = false}) {
    return [
      if (isHalfScreen) ...[
        const PopupMenuItem(
          value: 'reset_onboarding',
          child: Row(
            children: [
              Icon(Icons.restart_alt, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text('Refazer Cadastro / Trocar Modo'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'install_extensions',
          child: Row(
            children: [
              Icon(Icons.extension, color: Colors.blueAccent, size: 20),
              SizedBox(width: 8),
              Text('Instalar Extensões nos Navegadores'),
            ],
          ),
        ),
      ],
      const PopupMenuItem(
        value: 'debug_disable_anticheat',
        child: Row(
          children: [
            Icon(Icons.bug_report, color: Colors.purpleAccent, size: 20),
            SizedBox(width: 8),
            Text('🛠️ Sair do Anti-Cheat (Debug)'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'reset_full',
        child: Row(
          children: [
            Icon(Icons.restore, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Text('Reiniciar Banco Completo'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'reset_daily',
        child: Row(
          children: [
            Icon(Icons.history_toggle_off, color: Colors.blueAccent, size: 20),
            SizedBox(width: 8),
            Text('Zerar Consumo Diário'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'unlock_ratchet',
        child: Row(
          children: [
            const Icon(Icons.lock_open, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Text('Destravar Catraca ($_activeEntityId)'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'refill_tokens',
        child: Row(
          children: [
            Icon(Icons.token, color: Colors.purpleAccent, size: 20),
            SizedBox(width: 8),
            Text('Restaurar Tokens (+2)'),
          ],
        ),
      ),
    ];
  }

  void _toggleQuickTheme() async {
    final current = themeModeNotifier.value;
    final next = (current == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;
    themeModeNotifier.value = next;
    await setThemeMode(mode: next == ThemeMode.light ? 'light' : 'dark');
    if (mounted) setState(() {});
  }

  Widget _buildDesktopSidebar(BuildContext context, {required bool isCompactSidebar}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF15181E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF232730) : const Color(0xFFE2E8F0);

    final navItems = [
      (Icons.dashboard_outlined, Icons.dashboard, 'Tempo de Tela', 'Monitor em tempo real'),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'Estatísticas', 'Métricas de consumo'),
      (Icons.rule_folder_outlined, Icons.rule_folder, 'Regras & Whitelist', 'Limites e grupos'),
      (Icons.settings_outlined, Icons.settings, 'Configurações', 'Aparência e alertas'),
      (Icons.security_outlined, Icons.security, 'Quarentena', 'Modo nuke & bloqueios'),
      (Icons.storage_outlined, Icons.storage, 'SQLite / Testes', 'Depuração do banco'),
    ];

    return Container(
      width: isCompactSidebar ? 72 : 230,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: Column(
        children: [
          // Logo & Brand Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompactSidebar ? 8 : 16,
              vertical: 16,
            ),
            child: Row(
              mainAxisAlignment: isCompactSidebar ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.hourglass_bottom, color: Colors.tealAccent, size: 22),
                ),
                if (!isCompactSidebar) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chronos',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                        ),
                        Text(
                          'Focus Engine',
                          style: TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isCompactSidebar) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildModeBadge(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Divider(height: 1, color: borderColor),
          const SizedBox(height: 8),

          // Navigation Menu items
          Expanded(
            child: ListView.builder(
              itemCount: navItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemBuilder: (context, idx) {
                final item = navItems[idx];
                final isSelected = _currentTabIndex == idx;
                final activeColor = Colors.tealAccent;
                final inactiveColor = isDark ? Colors.white70 : const Color(0xFF475569);

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? Colors.teal.shade900.withValues(alpha: 0.45) : Colors.teal.shade50)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: isDark ? Colors.teal.shade700 : Colors.teal.shade300, width: 1)
                        : null,
                  ),
                  child: Tooltip(
                    message: isCompactSidebar ? item.$3 : '',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isCompactSidebar ? 0 : 12,
                        vertical: 2,
                      ),
                      leading: isCompactSidebar
                          ? Center(
                              child: Icon(
                                isSelected ? item.$2 : item.$1,
                                color: isSelected ? (isDark ? activeColor : Colors.teal.shade800) : inactiveColor,
                                size: 20,
                              ),
                            )
                          : Icon(
                              isSelected ? item.$2 : item.$1,
                              color: isSelected ? (isDark ? activeColor : Colors.teal.shade800) : inactiveColor,
                              size: 20,
                            ),
                      title: isCompactSidebar
                          ? null
                          : Text(
                              item.$3,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? (isDark ? Colors.white : Colors.teal.shade900) : inactiveColor,
                              ),
                            ),
                      subtitle: isCompactSidebar
                          ? null
                          : Text(
                              item.$4,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                      onTap: () => setState(() => _currentTabIndex = idx),
                    ),
                  ),
                );
              },
            ),
          ),

          // Sidebar Footer: Quick Theme Toggle & Anti-Cheat
          Divider(height: 1, color: borderColor),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Theme Toggle
                Tooltip(
                  message: isDark ? 'Alternar para Modo Claro' : 'Alternar para Modo Escuro',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: isCompactSidebar ? 0 : 10, vertical: 8),
                      side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                    ),
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 16,
                      color: isDark ? Colors.amberAccent : Colors.indigoAccent,
                    ),
                    label: isCompactSidebar
                        ? const SizedBox.shrink()
                        : Text(
                            isDark ? 'Modo Claro' : 'Modo Escuro',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF334155),
                            ),
                          ),
                    onPressed: _toggleQuickTheme,
                  ),
                ),
                const SizedBox(height: 8),
                // Anti-Cheat Button
                _buildAntiCheatButton(isCompact: isCompactSidebar),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(BuildContext context) {
    const titles = [
      'Tempo de Tela & Foco ao Vivo',
      'Estatísticas de Consumo & Histórico',
      'Regras de Bloqueio & Whitelist',
      'Configurações Gerais & Notificações',
      'Quarentena & Modo Nuke',
      'Banco de Dados & Testes SQLite',
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF15181E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF232730) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              titles[_currentTabIndex],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 14),
          ValueListenableBuilder<LiveEngineTick?>(
            valueListenable: _tickNotifier,
            builder: (context, tick, _) => _buildFocusBadge(tick ?? _latestTick),
          ),
          const Spacer(),

          // Ações do cabeçalho
          if (_antiCheatState?.isActive == true) ...[
            IconButton(
              tooltip: '🛠️ [DEBUG] Sair do Anti-Cheat',
              icon: const Icon(Icons.bug_report, color: Colors.purpleAccent, size: 20),
              onPressed: () async {
                final res = await debugDisableAntiCheat();
                _showSnack(res.message, res.success);
                await _refreshAntiCheat();
                _startStream();
              },
            ),
            const SizedBox(width: 4),
          ],

          IconButton(
            tooltip: 'Instalar Extensões em Navegadores',
            icon: const Icon(Icons.extension, color: Colors.blueAccent, size: 20),
            onPressed: () async {
              final res = await BrowserExtensionInstaller.installAll(
                isAntiCheatActive: _antiCheatState?.isActive ?? false,
                forceMandatory: true,
              );
              _showSnack(res.message, res.success);
            },
          ),

          PopupMenuButton<String>(
            tooltip: 'Ações Globais',
            icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : const Color(0xFF475569)),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => _buildMenuItems(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context, {required bool isHalfScreen, required bool isCompact}) {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.teal.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.hourglass_bottom, color: Colors.tealAccent, size: 20),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'Chronos',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          if (!isHalfScreen) ...[
            const SizedBox(width: 12),
            _buildModeBadge(),
          ],
          if (!isCompact) ...[
            const SizedBox(width: 10),
            ValueListenableBuilder<LiveEngineTick?>(
              valueListenable: _tickNotifier,
              builder: (context, tick, _) => _buildFocusBadge(tick ?? _latestTick),
            ),
          ],
        ],
      ),
      actions: [
        if (!isHalfScreen) ...[
          if (isCompact)
            IconButton(
              tooltip: 'Tela de Cadastro',
              icon: const Icon(Icons.settings_backup_restore, color: Colors.tealAccent, size: 18),
              onPressed: widget.onResetOnboarding,
            )
          else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                side: BorderSide(color: Colors.teal.shade400.withValues(alpha: 0.6)),
                foregroundColor: Colors.tealAccent,
              ),
              icon: const Icon(Icons.settings_backup_restore, size: 16),
              label: const Text('Tela de Cadastro', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: widget.onResetOnboarding,
            ),
            const SizedBox(width: 8),
          ],
        ],

        // Botão Anti-Cheat
        _buildAntiCheatButton(isCompact: isHalfScreen || isCompact),
        const SizedBox(width: 4),

        // Botão de Debug
        if (_antiCheatState?.isActive == true && !isHalfScreen)
          IconButton(
            tooltip: '🛠️ [DEBUG] Sair do Anti-Cheat Imediatamente',
            icon: const Icon(Icons.bug_report, color: Colors.purpleAccent),
            onPressed: () async {
              final res = await debugDisableAntiCheat();
              _showSnack(res.message, res.success);
              await _refreshAntiCheat();
              _startStream();
            },
          ),

        // Botão Instalação Rápida de Extensões
        if (!isHalfScreen)
          IconButton(
            tooltip: 'Instalar Extensões em Todos Navegadores',
            icon: const Icon(Icons.extension, color: Colors.blueAccent),
            onPressed: () async {
              final res = await BrowserExtensionInstaller.installAll(
                isAntiCheatActive: _antiCheatState?.isActive ?? false,
                forceMandatory: true,
              );
              _showSnack(res.message, res.success);
            },
          ),

        PopupMenuButton<String>(
          tooltip: 'Ações & Configuração',
          icon: const Icon(Icons.more_vert),
          onSelected: _handleMenuAction,
          itemBuilder: (context) => _buildMenuItems(isHalfScreen: isHalfScreen),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 760;
    final isCompactSidebar = screenWidth < 960;
    final isCompact = screenWidth < 900;
    final isHalfScreen = screenWidth < 780;

    final tabViews = [
      _buildDashboardTab(),
      const AnalyticsView(),
      RulesView(
        activeEntityId: _activeEntityId,
        onSelectEntity: (id) {
          _switchEntity(id);
          setState(() => _currentTabIndex = 0);
        },
        onRulesUpdated: () => _startStream(),
      ),
      GeneralSettingsView(
        onResetOnboarding: widget.onResetOnboarding,
        onSettingsChanged: () {
          _refreshAntiCheat();
          _startStream();
        },
      ),
      const QuarantineView(),
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DbTestPanel(
          activeEntityId: _activeEntityId,
          onDbChanged: () => _startStream(),
          onResetOnboarding: widget.onResetOnboarding,
        ),
      ),
    ];

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopSidebar(context, isCompactSidebar: isCompactSidebar),
            Expanded(
              child: Column(
                children: [
                  _buildDesktopHeader(context),
                  Expanded(
                    child: IndexedStack(
                      index: _currentTabIndex,
                      children: tabViews,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildMobileAppBar(context, isHalfScreen: isHalfScreen, isCompact: isCompact),
      body: IndexedStack(
        index: _currentTabIndex,
        children: tabViews,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tempo',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Métricas',
          ),
          NavigationDestination(
            icon: Icon(Icons.rule_folder_outlined),
            selectedIcon: Icon(Icons.rule_folder),
            label: 'Regras',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_outlined),
            selectedIcon: Icon(Icons.security),
            label: 'Nuke',
          ),
          NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: 'SQLite',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return ValueListenableBuilder<LiveEngineTick?>(
      valueListenable: _tickNotifier,
      builder: (context, liveTick, _) {
        final tick = liveTick ?? _latestTick;

        if (tick == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.tealAccent),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sincronizando com o motor de monitoramento...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: _startStream,
                    child: const Text('Tentar Conectar Agora'),
                  ),
                ],
              ),
            ),
          );
        }

        final isBlocked = tick.isBlocked;
        final isActiveNow = tick.isActiveNow;

        final currentEntity = tick.entityId.isEmpty
            ? (_activeEntityId == 'auto' ? 'youtube' : _activeEntityId)
            : tick.entityId;

        List<Map<String, dynamic>> activeSessions = [];
        if (tick.activeSessionsJson.isNotEmpty) {
          try {
            final parsed = jsonDecode(tick.activeSessionsJson);
            if (parsed is List) {
              activeSessions = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          } catch (_) {}
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isTwoColumn = constraints.maxWidth >= 880;

                final onboardingBanner = Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.teal.shade700.withValues(alpha: isDark ? 0.6 : 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_outlined, size: 18, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Etapa Inicial: teste a qualquer momento o cadastro e personalização de bloqueios.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          backgroundColor: isDark ? Colors.teal.shade800 : Colors.teal.shade100,
                          foregroundColor: isDark ? Colors.tealAccent : Colors.teal.shade900,
                        ),
                        icon: const Icon(Icons.settings_backup_restore, size: 16),
                        label: const Text(
                          'Voltar ao Cadastro',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: widget.onResetOnboarding,
                      ),
                    ],
                  ),
                );

                final sessionsContent = Column(
                  children: [
                    if (activeSessions.length > 1) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade900.withValues(alpha: isDark ? 0.3 : 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purpleAccent, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bolt, color: Colors.purpleAccent, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '⚡ ${activeSessions.length} Sessões Ativas Simultaneamente! O tempo de tela está sendo cronometrado em paralelo.',
                                style: const TextStyle(
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...activeSessions.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SessionCard(data: s),
                          )),
                    ] else if (activeSessions.length == 1) ...[
                      _SessionCard(data: activeSessions.first),
                    ] else ...[
                      _LiveMonitorCard(tick: tick),
                    ],
                  ],
                );

                final controlsContent = Column(
                  children: [
                    _QuotaControlsCard(
                      activeEntityId: currentEntity,
                      isBlocked: isBlocked,
                      onQuotaChanged: _showSnack,
                      onStreamRestart: _startStream,
                    ),
                    const SizedBox(height: 16),
                    DbTestPanel(
                      activeEntityId: currentEntity,
                      onDbChanged: _startStream,
                      onResetOnboarding: widget.onResetOnboarding,
                    ),
                  ],
                );

                final reconnectBanner = ValueListenableBuilder<bool>(
                  valueListenable: _isStreamErrorNotifier,
                  builder: (context, hasErr, _) {
                    if (!hasErr) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sincronizando com o motor de monitoramento...',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );

                if (isTwoColumn) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        reconnectBanner,
                        onboardingBanner,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 55, child: sessionsContent),
                            const SizedBox(width: 16),
                            Expanded(flex: 45, child: controlsContent),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      reconnectBanner,
                      onboardingBanner,
                      sessionsContent,
                      const SizedBox(height: 16),
                      controlsContent,
                    ],
                  ),
                );
              },
            ),

            // Overlay em tela cheia apenas quando bloqueado e ativo para APLICATIVOS nativos (não sites)
            if (isBlocked && isActiveNow && tick.targetType != 'SITE')
              FocusOverlay(
                tick: tick,
                onEmergencyTokenUsed: _startStream,
              ),
          ],
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SessionCard({required this.data});

  String _formatTime(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = data['display_name']?.toString() ?? 'Sessão';
    final isBlocked = data['is_blocked'] == true;
    final remainingSeconds = (data['remaining_seconds'] as num?)?.toInt() ?? 0;
    final totalQuota = (data['daily_quota_seconds'] as num?)?.toInt() ?? 0;
    final consumed = (data['consumed_seconds'] as num?)?.toInt() ?? 0;
    final targetType = data['target_type']?.toString() ?? 'GROUP';
    final detectedLabel = data['detected_activity_label']?.toString() ?? 'Em execução';

    final Color statusColor = isBlocked ? Colors.redAccent : Colors.tealAccent;
    final double progress = totalQuota > 0 ? (consumed / totalQuota).clamp(0.0, 1.0) : 0.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isBlocked
        ? (isDark ? Colors.red.shade900.withValues(alpha: 0.35) : Colors.red.shade50)
        : (isDark ? const Color(0xFF1C2027) : Colors.white);
    final subTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final tagBg = isDark ? Colors.black38 : const Color(0xFFF1F5F9);
    final tagTextColor = isDark ? Colors.white70 : const Color(0xFF334155);

    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBlocked ? Colors.redAccent : (targetType == 'SITE_GROUP' ? Colors.blueAccent : Colors.purpleAccent),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isBlocked ? Icons.gpp_bad : (targetType == 'SITE_GROUP' ? Icons.public : Icons.sports_esports),
                        color: statusColor,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isBlocked ? Colors.red.shade900 : Colors.teal.shade900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isBlocked ? 'BLOQUEADO' : 'TEMPO ATIVO',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatTime(remainingSeconds),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isBlocked ? Colors.redAccent : Colors.tealAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Consumido hoje: ${_formatTime(consumed)}',
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
                Text(
                  'Limite: ${_formatTime(totalQuota)} (${(progress * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.radar, size: 14, color: Colors.tealAccent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      detectedLabel,
                      style: TextStyle(color: tagTextColor, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMonitorCard extends StatelessWidget {
  final LiveEngineTick? tick;

  const _LiveMonitorCard({required this.tick});

  String _formatTime(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (tick == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final t = tick!;
    final isBlocked = t.isBlocked;
    final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final isRatchetLocked = t.ratchetLockedUntilUtc != null &&
        t.ratchetLockedUntilUtc! > nowEpoch;

    final Color statusColor = isBlocked
        ? Colors.redAccent
        : (t.isBackgroundPlayback
            ? Colors.blueAccent
            : (t.isActiveNow ? Colors.tealAccent : Colors.grey.shade400));

    final totalQuota = t.dailyQuotaSeconds;
    final consumed = t.consumedSeconds;
    final double progress = totalQuota > 0 ? (consumed / totalQuota).clamp(0.0, 1.0) : 0.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isBlocked
        ? (isDark ? Colors.red.shade900.withValues(alpha: 0.35) : Colors.red.shade50)
        : (isDark ? const Color(0xFF1C2027) : Colors.white);
    final subTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final tagBg = isDark ? Colors.black38 : const Color(0xFFF1F5F9);
    final tagTextColor = isDark ? Colors.white70 : const Color(0xFF334155);

    return Card(
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isBlocked ? Icons.gpp_bad : Icons.shield_rounded,
                        color: statusColor,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (isRatchetLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amberAccent, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_clock, size: 14, color: Colors.amberAccent),
                            SizedBox(width: 4),
                            Text(
                              'Catraca Ativa',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.purpleAccent, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.vpn_key, size: 14, color: Colors.purpleAccent),
                          const SizedBox(width: 4),
                          Text(
                            'Tokens: ${t.emergencyTokensRemaining}/2',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatTime(t.remainingSeconds),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isBlocked ? Colors.redAccent : Colors.tealAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Consumido hoje: ${_formatTime(consumed)}',
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
                Text(
                  'Limite de tempo de tela: ${_formatTime(totalQuota)} (${(progress * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    t.isActiveNow ? Icons.radar : Icons.nightlight_round,
                    size: 16,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t.detectedActivityLabel,
                      style: TextStyle(color: tagTextColor, fontSize: 13),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotaControlsCard extends StatelessWidget {
  final String activeEntityId;
  final bool isBlocked;
  final void Function(String msg, bool success) onQuotaChanged;
  final VoidCallback onStreamRestart;

  const _QuotaControlsCard({
    required this.activeEntityId,
    required this.isBlocked,
    required this.onQuotaChanged,
    required this.onStreamRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controles de Tempo de Tela & Catraca (Ratchet)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isFullWidth = constraints.maxWidth < 380;
                final btnList = <Widget>[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('Reduzir Tempo de Tela (Teste 15s)'),
                    onPressed: () async {
                      final res = await changeQuota(
                        entityId: activeEntityId,
                        newQuotaSeconds: 15,
                      );
                      onQuotaChanged(res.message, res.success);
                      onStreamRestart();
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Tentar Aumentar Tempo de Tela (+2h)'),
                    onPressed: () async {
                      final res = await changeQuota(
                        entityId: activeEntityId,
                        newQuotaSeconds: 7200,
                      );
                      onQuotaChanged(res.message, res.success);
                      onStreamRestart();
                    },
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.lock_clock, size: 18),
                    label: const Text('Trancar Catraca (24h)'),
                    onPressed: () async {
                      final ok = await lockRatchet(
                        entityId: activeEntityId,
                        hours: 24,
                      );
                      if (ok) {
                        onQuotaChanged('Catraca trancada por 24h! Aumentos proibidos.', true);
                        onStreamRestart();
                      }
                    },
                  ),
                  if (isBlocked)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                      ),
                      icon: const Icon(Icons.warning_amber, size: 18),
                      label: const Text('Usar Token de Emergência (+1h)'),
                      onPressed: () async {
                        final res = await consumeEmergencyToken(entityId: activeEntityId);
                        onQuotaChanged(res.message, res.success);
                        onStreamRestart();
                      },
                    ),
                ];

                if (isFullWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final btn in btnList)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: btn,
                        ),
                    ],
                  );
                }

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: btnList,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
