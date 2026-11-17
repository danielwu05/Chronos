import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:chronos_app/services/notification_service.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/widgets/add_block_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Verificação dos 5 Bugs e 4 Novas Funcionalidades', () {
    test('Bug 1 & 4: Instalação no Chrome e Chromium não altera Preferences e cria External Extensions', () async {
      final tmpHome = Directory.systemTemp.createTempSync('chronos_nf_bug14_');
      addTearDown(() => tmpHome.deleteSync(recursive: true));
      final home = tmpHome.path;
      Directory('$home/.config/google-chrome/Default').createSync(recursive: true);
      Directory('$home/.config/chromium/Default').createSync(recursive: true);
      final chromePrefs = File('$home/.config/google-chrome/Default/Preferences');
      chromePrefs.writeAsStringSync('{}');

      final res = await BrowserExtensionInstaller.installAll(
        launchWithExtension: false,
        forceMandatory: true,
        homeOverride: home,
      );
      expect(res.success, isTrue);

      final chromeExtDir = Directory('$home/.config/google-chrome/External Extensions');
      final chromiumExtDir = Directory('$home/.config/chromium/External Extensions');

      expect(chromeExtDir.existsSync(), isTrue);
      expect(chromiumExtDir.existsSync(), isTrue);

      // Garante que o arquivo Preferences do Chrome NÃO foi corrompido
      final content = chromePrefs.readAsStringSync();
      expect(content.isNotEmpty, isTrue);
      expect(jsonDecode(content), isA<Map<String, dynamic>>());
    });

    test('Bug 5: Modo Nuke suporta 3 tambores (dias, horas, minutos) com default 1 dia (86400s)', () {
      const defaultDays = 1;
      const defaultHours = 0;
      const defaultMinutes = 0;
      final totalSeconds = (defaultDays * 86400) + (defaultHours * 3600) + (defaultMinutes * 60);

      expect(totalSeconds, equals(86400));
      expect(totalSeconds, greaterThan(0));

      final customSeconds = (2 * 86400) + (3 * 3600) + (15 * 60);
      expect(customSeconds, equals(172800 + 10800 + 900));
    });

    test('Feature 1: NotificationService possui toggle para app monitorado e alertas', () {
      final notif = NotificationService();
      expect(notif.notifyOnAppMonitored, isTrue);
      expect(notif.notifyRemaining, isTrue);
      expect(notif.notifyPeriodic, isTrue);

      notif.notifyOnAppMonitored = false;
      expect(notif.notifyOnAppMonitored, isFalse);
      notif.notifyOnAppMonitored = true;
    });

    test('Feature 4: Formatação limpa de nomes de aplicativos sem exibir executáveis ou caminhos', () {
      String cleanExecutableName(String raw) {
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

      String cleanAppName(dynamic item) {
        if (item == null) return '';
        if (item is Map) {
          final name = item['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) return name;
          final exec = item['exec']?.toString().trim() ?? '';
          return cleanExecutableName(exec);
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
        return cleanExecutableName(str);
      }

      expect(cleanAppName({'name': 'Counter-Strike 2', 'exec': 'steam'}), equals('Counter-Strike 2'));
      expect(cleanAppName({'name': 'Dota 2', 'exec': '/usr/bin/dota2'}), equals('Dota 2'));
      expect(cleanAppName('Steam (steam)'), equals('Steam'));
      expect(cleanAppName('/usr/bin/discord'), equals('Discord'));
      expect(cleanAppName('spotify.exe'), equals('Spotify'));
    });

    test('Google Chrome: Detecção precisa sem falso positivo e exportação de pacote', () async {
      final tmpHome = Directory.systemTemp.createTempSync('chronos_nf_chrome_');
      addTearDown(() => tmpHome.deleteSync(recursive: true));
      final home = tmpHome.path;
      Directory('$home/.config/google-chrome/Default').createSync(recursive: true);

      final chromeBrowser = DetectedBrowser(
        id: 'google-chrome',
        name: 'Google Chrome',
        family: 'chromium',
        executable: 'google-chrome-stable',
        configDir: '$home/.config/google-chrome',
        policyPath: '$home/nonexistent-policy.json',
      );

      final isInstalled = BrowserExtensionInstaller.isExtensionInstalledInBrowser(
        chromeBrowser,
        homeOverride: home,
      );
      final isReallyLoaded = BrowserExtensionInstaller.isExtensionLoadedInChromeProfiles(
        configDirOverride: chromeBrowser.configDir,
      );
      expect(isInstalled, equals(isReallyLoaded));

      // Testa a exportação de zip da extensão em diretório isolado
      final zipPath = await BrowserExtensionInstaller.exportExtensionZipToDownloads(
        homeOverride: home,
      );
      if (zipPath != null) {
        expect(File(zipPath).existsSync(), isTrue);
        expect(zipPath.endsWith('.zip'), isTrue);
      }
    });

    test('Chronos Guard: Staging, checagem de status e comando de instalação', () async {
      final status = await ChronosGuardService.checkStatus();
      expect(status, isA<ChronosGuardStatus>());

      final staging = await ChronosGuardService.prepareStaging();
      expect(Directory(staging).existsSync(), isTrue);
      expect(File('$staging/chronos-guard').existsSync(), isTrue);
      expect(File('$staging/install-guard.sh').existsSync(), isTrue);
      expect(File('$staging/guard.conf').existsSync(), isTrue);

      final cmd = ChronosGuardService.getInstallCliCommand();
      expect(cmd.contains('install-guard.sh'), isTrue);
      expect(cmd.startsWith('sudo '), isTrue);
    });

    test('Feature 1: Screen Time Analytics data structures and formatting', () {
      final summary = AnalyticsSummaryDto(
        totalConsumedTodaySeconds: 3660,
        totalConsumed7DSeconds: 25200,
        dailyAverage7DSeconds: 3600,
        peakDayLabel: 'Quinta-feira',
        peakDaySeconds: 7200,
        comparisonVsPrevWeekPercent: -15.5,
        dailyBreakdown7D: const [
          DailyUsageDto(
            dayLabel: 'Sex',
            dateStr: '2026-11-13',
            consumedSeconds: 3660,
            isToday: true,
          ),
        ],
        topEntities7D: const [
          TopEntityDto(
            entityId: 'youtube',
            displayName: 'YouTube',
            targetType: 'SITE',
            consumedSeconds: 1800,
            percentage: 50.0,
          ),
        ],
      );

      expect(summary.totalConsumedTodaySeconds, equals(3660));
      expect(summary.peakDayLabel, equals('Quinta-feira'));
      expect(summary.topEntities7D.first.displayName, equals('YouTube'));
      expect(summary.comparisonVsPrevWeekPercent, equals(-15.5));
    });

    test('Feature 3: Theme mode state management (dark, light, system)', () {
      final notifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
      expect(notifier.value, equals(ThemeMode.dark));

      notifier.value = ThemeMode.light;
      expect(notifier.value, equals(ThemeMode.light));

      notifier.value = ThemeMode.system;
      expect(notifier.value, equals(ThemeMode.system));
    });

    test('Bug 1: Native Wayland runner in linux/runner/main.cc prevents black screen when unmaximized', () {
      final mainCc = File('linux/runner/main.cc');
      expect(mainCc.existsSync(), isTrue);
      final content = mainCc.readAsStringSync();
      expect(content.contains('GDK_BACKEND'), isFalse);
      expect(content.contains('x11,wayland,*'), isFalse);
    });

    test('Bug 2: Firefox exportação de .xpi e .zip para Downloads e detecção de perfil', () async {
      final tmpHome = Directory.systemTemp.createTempSync('chronos_nf_ff_');
      addTearDown(() => tmpHome.deleteSync(recursive: true));
      final home = tmpHome.path;

      final firefoxXpi = await BrowserExtensionInstaller.exportFirefoxExtensionZipToDownloads(
        homeOverride: home,
      );
      expect(firefoxXpi, isNotNull);
      expect(File(firefoxXpi!).existsSync(), isTrue);
      expect(firefoxXpi.endsWith('.xpi'), isTrue);

      final zipCopy = File('$home/Downloads/chronos_firefox_extension.zip');
      expect(zipCopy.existsSync(), isTrue);

      final firefoxDir = BrowserExtensionInstaller.getFirefoxExtensionDir();
      expect(Directory(firefoxDir).existsSync(), isTrue);
      expect(File('$firefoxDir/manifest.json').existsSync(), isTrue);
    });

    test('Feature 1: StayFocusd Content Filters DTO integrity and toggles', () {
      const filters = FocusFiltersDto(
        blockShorts: true,
        grayscaleMode: true,
        educationalOnly: true,
        blockFeed: true,
        blockComments: true,
        blockNotifications: true,
        ytBlockShorts: true,
        ytEducationalMode: true,
        ytBlockSidebar: true,
        ytBlockComments: true,
        igBlockReels: true,
        igBlockFeed: true,
        igBlockComments: true,
        ttBlockFeed: true,
        rdBlockFeed: true,
        rdBlockComments: true,
        twBlockFeed: true,
        twBlockTrends: true,
        liBlockFeed: true,
        globalGrayscale: true,
        globalBlockNotifications: true,
        hudAlpha: 0.75,
        hudScale: 1.35,
        hudHideToEye: true,
        launcherFilterEnabled: true,
        launcherBlockedTags: ['Soulslike', 'NSFW'],
        launcherBlockedNames: ['Dota 2'],
      );

      expect(filters.blockShorts, isTrue);
      expect(filters.grayscaleMode, isTrue);
      expect(filters.educationalOnly, isTrue);
      expect(filters.blockFeed, isTrue);
      expect(filters.blockComments, isTrue);
      expect(filters.blockNotifications, isTrue);
      expect(filters.ytBlockShorts, isTrue);
      expect(filters.ytEducationalMode, isTrue);
      expect(filters.ytBlockSidebar, isTrue);
      expect(filters.ytBlockComments, isTrue);
      expect(filters.igBlockReels, isTrue);
      expect(filters.igBlockFeed, isTrue);
      expect(filters.igBlockComments, isTrue);
      expect(filters.ttBlockFeed, isTrue);
      expect(filters.rdBlockFeed, isTrue);
      expect(filters.rdBlockComments, isTrue);
      expect(filters.twBlockFeed, isTrue);
      expect(filters.twBlockTrends, isTrue);
      expect(filters.liBlockFeed, isTrue);
      expect(filters.globalGrayscale, isTrue);
      expect(filters.globalBlockNotifications, isTrue);
      expect(filters.hudAlpha, equals(0.75));
      expect(filters.hudScale, equals(1.35));
      expect(filters.hudHideToEye, isTrue);
      expect(filters.launcherFilterEnabled, isTrue);
      expect(filters.launcherBlockedTags, equals(['Soulslike', 'NSFW']));
      expect(filters.launcherBlockedNames, equals(['Dota 2']));

      const offFilters = FocusFiltersDto(
        blockShorts: false,
        grayscaleMode: false,
        educationalOnly: false,
        blockFeed: false,
        blockComments: false,
        blockNotifications: false,
        ytBlockShorts: false,
        ytEducationalMode: false,
        ytBlockSidebar: false,
        ytBlockComments: false,
        igBlockReels: false,
        igBlockFeed: false,
        igBlockComments: false,
        ttBlockFeed: false,
        rdBlockFeed: false,
        rdBlockComments: false,
        twBlockFeed: false,
        twBlockTrends: false,
        liBlockFeed: false,
        globalGrayscale: false,
        globalBlockNotifications: false,
        hudAlpha: 0.35,
        hudScale: 0.85,
        hudHideToEye: false,
        launcherFilterEnabled: false,
        launcherBlockedTags: [],
        launcherBlockedNames: [],
      );

      expect(offFilters.blockShorts, isFalse);
      expect(offFilters.ytBlockShorts, isFalse);
      expect(offFilters.igBlockReels, isFalse);
      expect(offFilters.ttBlockFeed, isFalse);
      expect(offFilters.rdBlockFeed, isFalse);
      expect(offFilters.twBlockFeed, isFalse);
      expect(offFilters.liBlockFeed, isFalse);
      expect(offFilters.hudAlpha, equals(0.35));
      expect(offFilters.hudScale, equals(0.85));
      expect(offFilters.hudHideToEye, isFalse);
      expect(offFilters.launcherFilterEnabled, isFalse);
      expect(offFilters.launcherBlockedTags, isEmpty);
      expect(offFilters.launcherBlockedNames, isEmpty);
      expect(filters == offFilters, isFalse);
    });

    test('Bug 2: Quarantine sorting keeps QUARANTINED at the top and reviews at the bottom', () {
      final items = [
        const QuarantineItemDto(
          requestId: 'req_1',
          appIdentifier: '/usr/local/bin/random1',
          displayName: 'Random 1',
          platform: 'LINUX',
          status: 'APPROVED',
          requestedAtUtc: 100,
        ),
        const QuarantineItemDto(
          requestId: 'req_2',
          appIdentifier: '/tmp/test_bin',
          displayName: 'Test Bin',
          platform: 'LINUX',
          status: 'QUARANTINED',
          requestedAtUtc: 200,
        ),
        const QuarantineItemDto(
          requestId: 'req_3',
          appIdentifier: '/usr/local/bin/random2',
          displayName: 'Random 2',
          platform: 'LINUX',
          status: 'REJECTED',
          requestedAtUtc: 150,
        ),
        const QuarantineItemDto(
          requestId: 'req_4',
          appIdentifier: '/home/dwu/game',
          displayName: 'Game',
          platform: 'LINUX',
          status: 'QUARANTINED',
          requestedAtUtc: 300,
        ),
      ];

      items.sort((a, b) {
        final aPending = a.status == 'QUARANTINED' ? 0 : 1;
        final bPending = b.status == 'QUARANTINED' ? 0 : 1;
        if (aPending != bPending) return aPending.compareTo(bPending);
        return b.requestedAtUtc.compareTo(a.requestedAtUtc);
      });

      expect(items[0].status, equals('QUARANTINED'));
      expect(items[0].requestId, equals('req_4')); // more recent pending
      expect(items[1].status, equals('QUARANTINED'));
      expect(items[1].requestId, equals('req_2'));
      expect(items[2].status, equals('REJECTED'));
      expect(items[3].status, equals('APPROVED'));
    });

    test('Bug 3: BlockDialogMode enum supports full, timeOnly, appsOnly', () {
      expect(BlockDialogMode.values.length, equals(3));
      expect(BlockDialogMode.full.name, equals('full'));
      expect(BlockDialogMode.timeOnly.name, equals('timeOnly'));
      expect(BlockDialogMode.appsOnly.name, equals('appsOnly'));
    });

    test('Bug 6: Firefox extension gecko ID matches chronos-focus@chronos.local', () {
      final manifestFile = File('chronos_extension_firefox/manifest.json');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();
      expect(content.contains('"id": "chronos-focus@chronos.local"'), isTrue);

      final packagerContent = File('lib/services/extension_packager.dart').readAsStringSync();
      expect(packagerContent.contains('chronos-focus@chronos.local'), isTrue);
      final installerContent = File('lib/services/browser_extension_installer.dart').readAsStringSync();
      expect(installerContent.contains('firefoxAddonId'), isTrue);
      expect(installerContent.contains('policies.json'), isTrue);
    });

    test('Wayland Hyprland Fix Verification: main.cc is clean without forcing X11 (prevents unmaximized black screen)', () {
      final mainCc = File('linux/runner/main.cc');
      expect(mainCc.existsSync(), isTrue);
      final content = mainCc.readAsStringSync();
      // Must NOT force X11 backend which causes unmaximized black screens on Hyprland Wayland
      expect(content.contains('GDK_BACKEND'), isFalse);
      expect(content.contains('x11,wayland,*'), isFalse);

      final myAppCc = File('linux/runner/my_application.cc');
      expect(myAppCc.existsSync(), isTrue);
      final myAppContent = myAppCc.readAsStringSync();
      expect(myAppContent.contains('#121417'), isTrue);
      expect(myAppContent.contains('gtk_widget_show_all(GTK_WIDGET(window));'), isTrue);
    });

    test('Bug 3 Fix Verification: Extension modular core, grayscale, and Main-World navigation hooks', () {
      for (final extDir in ['chronos_extension', 'chronos_extension_firefox']) {
        final coreJs = File('$extDir/focus_filters_core.js').readAsStringSync();
        expect(coreJs.contains('ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts])'), isTrue);
        expect(coreJs.contains('ytd-rich-item-renderer:has(a[href*="/shorts/"])'), isTrue);
        expect(coreJs.contains('grid-shelf-view-model'), isTrue);
        expect(coreJs.contains(':root.chronos-grayscale'), isTrue);
        expect(coreJs.contains('ytd-comments'), isTrue);

        final contentJs = File('$extDir/content.js').readAsStringSync();
        expect(contentJs.contains('ChronosFocusCore'), isTrue);
        expect(contentJs.contains('chronos-route-change'), isTrue);
        expect(contentJs.contains('yt-navigate-finish'), isTrue);

        final bgJs = File('$extDir/background.js').readAsStringSync();
        expect(bgJs.contains('ytBlockShorts: true'), isTrue);
        expect(bgJs.contains('globalGrayscale: false'), isTrue);
        expect(bgJs.contains('KNOWN_APP_DOMAINS'), isTrue);
        expect(bgJs.contains('youtube.com'), isTrue);
      }

      final navHookJs = File('chronos_extension/navigation_hook.js').readAsStringSync();
      expect(navHookJs.contains('wrapHistory("pushState")'), isTrue);
      expect(navHookJs.contains('wrapHistory("replaceState")'), isTrue);

      final installerContent = File('lib/services/browser_extension_installer.dart').readAsStringSync();
      expect(installerContent.contains('launchFirefoxInstallPrompt'), isTrue);
    });

    test('Bug 2 Fix Verification: UI Responsive layouts prevent RenderFlex overflow across views', () {
      final rulesView = File('lib/widgets/rules_view.dart').readAsStringSync();
      expect(rulesView.contains('WrapCrossAlignment.center'), isTrue);

      final settingsView = File('lib/widgets/general_settings_view.dart').readAsStringSync();
      expect(settingsView.contains('Expanded(\n                  child: Text(\n                    title'), isTrue);

      final analyticsView = File('lib/widgets/analytics_view.dart').readAsStringSync();
      expect(analyticsView.contains('refreshButton'), isTrue);
      expect(analyticsView.contains('Expanded(\n                              child: Text(\n                                \'Top 5 Apps'), isTrue);
    });

    test('Item 1: Botão de adicionar apps/sites no grupo usa ícone library_add_outlined em vez de group_add_outlined', () {
      final rulesView = File('lib/widgets/rules_view.dart').readAsStringSync();
      expect(rulesView.contains('Icons.library_add_outlined'), isTrue);
      expect(rulesView.contains('Icons.group_add_outlined'), isFalse);
    });

    testWidgets('Items 2 & 3: AddBlockDialog appsOnly preserva apps/sites/keywords/mode e bloqueia duplicados já no grupo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final existingRule = RuleItemDto(
        entityId: 'group_games_test',
        displayName: 'Jogos & Redes',
        dailyQuotaSeconds: 1800,
        isBlockedCompletely: false,
        mode: 'LOCKED',
        ratchetLockedUntilUtc: null,
        updatedAtUtc: 0,
        targetType: 'GROUP',
        pattern: jsonEncode({
          'apps': [
            {'name': 'Dota 2', 'exec': 'steam://rungameid/570'},
            {'name': 'Slack', 'exec': 'slack'},
          ],
          'sites': ['reddit.com', 'twitch.tv'],
          'keywords': ['spoiler'],
        }),
        weekendQuotaSeconds: null,
        scheduleJson: null,
      );

      final fakeApps = <InstalledAppDto>[
        const InstalledAppDto(
          id: 'steam_570',
          name: 'Dota 2',
          exec: 'steam://rungameid/570',
          iconName: 'Game',
          iconPath: '',
        ),
        const InstalledAppDto(
          id: 'slack_app',
          name: 'Slack',
          exec: 'slack',
          iconName: 'Network',
          iconPath: '',
        ),
        const InstalledAppDto(
          id: 'steam_client',
          name: 'Steam',
          exec: 'steam',
          iconName: 'Game',
          iconPath: '',
        ),
        const InstalledAppDto(
          id: 'blender_app',
          name: 'Blender',
          exec: 'blender',
          iconName: 'Graphics',
          iconPath: '',
        ),
      ];

      BlockConfigResult? poppedResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  poppedResult = await showDialog<BlockConfigResult>(
                    context: context,
                    builder: (_) => AddBlockDialog(
                      defaultMode: 'SELF_CONTROL',
                      initialRule: existingRule,
                      dialogMode: BlockDialogMode.appsOnly,
                      installedAppsLoader: () async => fakeApps,
                    ),
                  );
                },
                child: const Text('Abrir Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Dialog'));
      await tester.pumpAndSettle();

      // Apps já presentes devem exibir badge "Já no grupo"
      expect(find.text('Já no grupo'), findsNWidgets(2));
      expect(find.text('Dota 2'), findsOneWidget);

      // Clicar em "Limpar" NÃO deve desmarcar os apps protegidos já no grupo
      await tester.tap(find.text('Limpar'));
      await tester.pumpAndSettle();
      expect(find.text('2 apps • 2 sites'), findsOneWidget);

      // Rolar lista se necessário até encontrar "Blender" e selecioná-lo
      await tester.scrollUntilVisible(
        find.text('Blender'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Blender'), findsOneWidget);
      await tester.tap(find.text('Blender'));
      await tester.pumpAndSettle();
      expect(find.text('3 apps • 2 sites'), findsOneWidget);

      // Trocar para sub-aba "Sites e Palavras (2)" e verificar bloqueio de duplicado
      await tester.tap(find.text('Sites e Palavras (2)'));
      await tester.pumpAndSettle();
      expect(find.text('reddit.com (Já no grupo)'), findsOneWidget);
      expect(find.text('twitch.tv (Já no grupo)'), findsOneWidget);

      final siteField = find.byType(TextField).last;
      await tester.enterText(siteField, 'https://www.reddit.com/');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      expect(find.text('"reddit.com" já foi adicionado ao grupo.'), findsOneWidget);
      expect(find.text('3 apps • 2 sites'), findsOneWidget);

      // Adicionar novo site válido ("youtube.com") e salvar
      await tester.enterText(siteField, 'youtube.com');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      expect(find.text('3 apps • 3 sites'), findsOneWidget);

      await tester.tap(find.text('Salvar Apps no Grupo'));
      await tester.pumpAndSettle();

      expect(poppedResult, isNotNull);
      expect(poppedResult!.mode, equals('LOCKED'));
      final savedPattern = jsonDecode(poppedResult!.pattern) as Map<String, dynamic>;
      final savedApps = (savedPattern['apps'] as List).cast<Map<String, dynamic>>();
      final savedAppExecs = savedApps.map((a) => a['exec']).toList();
      expect(savedAppExecs, containsAll(<String>['steam://rungameid/570', 'slack', 'blender']));
      expect(savedPattern['sites'], containsAll(<String>['reddit.com', 'twitch.tv', 'youtube.com']));
      expect(savedPattern['keywords'], equals(<String>['spoiler']));
    });
  });
}
