import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:chronos_app/services/chronos_daemon_service.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

class WebBlockServer {
  static HttpServer? _server;
  static int _port = 4545;
  static bool _isRunning = false;
  static final StreamController<int> _sseController =
      StreamController<int>.broadcast();

  static int get port => _port;
  static bool get isRunning => _isRunning;

  /// Dispara notificação imediata para clientes SSE e watchdog interno.
  static void nudgeObservers() {
    _filtersRevision++;
    if (!_sseController.isClosed) {
      _sseController.add(_filtersRevision);
    }
  }

  static Future<bool> start({int port = 4545}) async {
    if (_isRunning) return true;

    // If persistent chronos_proxy daemon already owns 127.0.0.1:4545, reuse it cleanly
    // instead of falling back to an unreachable ephemeral port.
    if (port == 4545 && await ChronosDaemonService.isApiDaemonHealthy(port: port)) {
      _port = port;
      _isRunning = true;
      if (kDebugMode) {
        debugPrint('Chronos WebBlockServer conectado ao daemon persistente em http://127.0.0.1:$_port');
      }
      return true;
    }

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _port = _server!.port;
      _isRunning = true;
      if (kDebugMode) {
        debugPrint('Chronos WebBlockServer rodando em http://127.0.0.1:$_port');
      }

      _server!.listen(_handleRequest, onError: (e) {
        if (kDebugMode) {
          debugPrint('Erro no WebBlockServer: $e');
        }
      });
      return true;
    } catch (e) {
      // Tenta uma porta alternativa se 4545 estiver ocupada
      try {
        _server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
          shared: true,
        );
        _port = _server!.port;
        _isRunning = true;
        if (kDebugMode) {
          debugPrint('Chronos WebBlockServer rodando em porta dinâmica http://127.0.0.1:$_port');
        }
        _server!.listen(_handleRequest);
        return true;
      } catch (err) {
        if (kDebugMode) {
          debugPrint('Falha fatal ao iniciar WebBlockServer: $err');
        }
        return false;
      }
    }
  }

  static Future<void> stop() async {
    _isRunning = false;
    await _server?.close(force: true);
    _server = null;
  }

  static void _addCorsHeaders(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final res = request.response;
    _addCorsHeaders(res);

    if (request.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/api/status') {
        await _handleApiStatus(request, res);
      } else if (path == '/api/focus-filters') {
        await _handleFocusFilters(request, res);
      } else if (path == '/api/language') {
        await _handleLanguage(request, res);
      } else if (path == '/api/events') {
        await _handleEvents(res);
      } else if (path == '/api/nudge') {
        nudgeObservers();
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'success': true,
          'stateRevision': _filtersRevision,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        await res.close();
      } else if (path == '/api/launchers/resolve') {
        await _handleLaunchersResolve(request, res);
      } else if (path == '/api/launchers/tags') {
        await _handleLaunchersTags(request, res);
      } else if (path == '/api/launchers/autocomplete') {
        await _handleLaunchersAutocomplete(request, res);
      } else if (path == '/api/check') {
        await _handleApiCheck(request, res);
      } else if (path == '/api/emergency-token' && request.method == 'POST') {
        await _handleEmergencyToken(request, res);
      } else if (path == '/proxy.pac') {
        await _handleProxyPac(res);
      } else if (path == '/' || path == '/blocked' || path == '/blocked.html') {
        await _handleBlockedPage(request, res);
      } else if (path == '/api/tab_closed') {
        _clearActiveBrowserTab();
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'success': true, 'timestamp': DateTime.now().millisecondsSinceEpoch}));
        await res.close();
      } else if (path == '/api/ping') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'pong': true, 'timestamp': DateTime.now().millisecondsSinceEpoch}));
        await res.close();
      } else {
        res.statusCode = HttpStatus.notFound;
        res.headers.contentType = ContentType.text;
        res.write('404 - Rota não encontrada no Chronos Server');
        await res.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro na requisição: $e');
      res.statusCode = HttpStatus.internalServerError;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'error': e.toString()}));
      await res.close();
    }
  }

  static void _recordActiveBrowserTab(
    String url,
    String title, {
    String audibleUrl = '',
    String audibleTitle = '',
  }) {
    final cleanUrl = url.trim();
    final cleanAudible = audibleUrl.trim();
    if (cleanUrl.isEmpty && cleanAudible.isEmpty) {
      return;
    }
    try {
      final f = File('/tmp/chronos_active_tab.json');
      f.writeAsStringSync(jsonEncode({
        'url': cleanUrl.contains('127.0.0.1:4545') ? '' : cleanUrl,
        'title': title.trim(),
        'audible_url': cleanAudible.contains('127.0.0.1:4545') ? '' : cleanAudible,
        'audible_title': audibleTitle.trim(),
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  static void _clearActiveBrowserTab() {
    try {
      final f = File('/tmp/chronos_active_tab.json');
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  static const Map<String, List<String>> _knownAppDomains = {
    'youtube': ['youtube.com', 'youtu.be'],
    'instagram': ['instagram.com'],
    'tiktok': ['tiktok.com'],
    'reddit': ['reddit.com', 'old.reddit.com'],
    'twitter': ['twitter.com', 'x.com'],
    'x': ['x.com', 'twitter.com'],
    'linkedin': ['linkedin.com'],
    'twitch': ['twitch.tv'],
    'netflix': ['netflix.com'],
    'facebook': ['facebook.com'],
    'discord': ['discord.com'],
    'spotify': ['open.spotify.com'],
  };

  /// Deterministic fail-open PAC file pointing browsers to the local selective proxy (127.0.0.1:4546).
  static String buildProxyPacContent({int proxyPort = 4546}) {
    return '''function FindProxyForURL(url, host) {
  if (isPlainHostName(host) ||
      shExpMatch(host, "127.*") ||
      shExpMatch(host, "10.*") ||
      shExpMatch(host, "192.168.*") ||
      host === "localhost" ||
      host === "::1") {
    return "DIRECT";
  }
  return "PROXY 127.0.0.1:$proxyPort; DIRECT";
}
''';
  }

  static int _filtersRevision = 1;

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

  static List<String> _parseStringListField(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final cleaned = item?.toString().trim() ?? '';
      if (cleaned.isEmpty) continue;
      final norm = _normalizeLauncherText(cleaned);
      if (seen.add(norm)) {
        out.add(cleaned);
      }
    }
    return out;
  }

  static String _normalizeLauncherText(String input) {
    const accents = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final ch in input.trim().toLowerCase().split('')) {
      buf.write(accents[ch] ?? ch);
    }
    return buf.toString();
  }

  static int? _extractSteamAppIdFromUrl(String url) {
    final candidates = <String>[url];
    if (url.contains('%')) {
      try {
        candidates.add(Uri.decodeComponent(url));
      } catch (_) {}
    }
    for (final c in candidates) {
      final m1 = RegExp(r'(?:^|/|[=?&])app/(\d+)', caseSensitive: false).firstMatch(c);
      if (m1 != null) return int.tryParse(m1.group(1)!);
      final m2 = RegExp(r'[?&]appid=(\d+)', caseSensitive: false).firstMatch(c);
      if (m2 != null) return int.tryParse(m2.group(1)!);
    }
    return null;
  }

  static bool _isUmbrellaAdultTag(String norm) =>
      norm == 'nsfw' ||
      norm == 'conteudo adulto' ||
      norm == 'adult only' ||
      norm == 'adulto' ||
      norm == 'adult' ||
      norm == '18+';

  static bool _isExplicitAdultTagCandidate(String norm) =>
      norm == 'hentai' ||
      norm == 'nsfw' ||
      norm == 'sexual content' ||
      norm == 'conteudo sexual' ||
      norm == 'nudity' ||
      norm == 'nudez' ||
      norm == 'sexual themes' ||
      norm == 'conteudo adulto' ||
      norm == 'adult only' ||
      norm == 'erotic' ||
      norm == 'eroge';

  static Map<String, dynamic> _filtersToMap(FocusFiltersDto f) => {
    'blockShorts': false,
    'grayscaleMode': f.globalGrayscale,
    'educationalOnly': false,
    'blockFeed': false,
    'blockComments': false,
    'blockNotifications': f.globalBlockNotifications,
    'ytBlockShorts': f.ytBlockShorts,
    'ytEducationalMode': f.ytEducationalMode,
    'ytBlockSidebar': f.ytBlockSidebar,
    'ytBlockComments': f.ytBlockComments,
    'igBlockReels': f.igBlockReels,
    'igBlockFeed': f.igBlockFeed,
    'igBlockComments': f.igBlockComments,
    'ttBlockFeed': f.ttBlockFeed,
    'rdBlockFeed': f.rdBlockFeed,
    'rdBlockComments': f.rdBlockComments,
    'twBlockFeed': f.twBlockFeed,
    'twBlockTrends': f.twBlockTrends,
    'liBlockFeed': f.liBlockFeed,
    'globalGrayscale': f.globalGrayscale,
    'globalBlockNotifications': f.globalBlockNotifications,
    'hudAlpha': f.hudAlpha.clamp(0.15, 1.0),
    'hudHideToEye': f.hudHideToEye,
    'hudScale': (f.hudScale.isFinite ? f.hudScale : 1.0).clamp(0.70, 1.60),
    'launcherFilterEnabled': f.launcherFilterEnabled,
    'launcherBlockedTags': f.launcherBlockedTags,
    'launcherBlockedNames': f.launcherBlockedNames,
  };

  static String _computeFiltersRevision(
    FocusFiltersDto f, {
    bool antiCheatActive = false,
    String antiCheatMode = 'OFF',
  }) {
    final payload = jsonEncode(_filtersToMap(f));
    final acFlag = antiCheatActive ? 1 : 0;
    return '$_filtersRevision:$acFlag:$antiCheatMode:${payload.hashCode.toUnsigned(32)}';
  }

  static ({
    List<String> sites,
    List<Map<String, String>> apps,
    List<String> keywords,
  }) _parseGroupPatternDetails(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (sites: <String>[], apps: <Map<String, String>>[], keywords: <String>[]);
    }
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final sites = <String>[];
          final rawSites = decoded['sites'];
          if (rawSites is List) {
            for (final s in rawSites) {
              if (s is String && s.trim().isNotEmpty) {
                sites.add(s.trim());
              } else if (s is Map) {
                final v = (s['domain'] ?? s['url'] ?? s['name'] ?? '').toString().trim();
                if (v.isNotEmpty) sites.add(v);
              }
            }
          }
          final apps = <Map<String, String>>[];
          final rawApps = decoded['apps'];
          if (rawApps is List) {
            for (final a in rawApps) {
              if (a is String && a.trim().isNotEmpty) {
                apps.add({'name': a.trim(), 'exec': a.trim()});
              } else if (a is Map) {
                final n = (a['name'] ?? '').toString().trim();
                final e = (a['exec'] ?? n).toString().trim();
                if (n.isNotEmpty || e.isNotEmpty) {
                  apps.add({'name': n.isNotEmpty ? n : e, 'exec': e});
                }
              }
            }
          }
          final keywords = _parseStringListField(decoded['keywords']);
          return (sites: sites, apps: apps, keywords: keywords);
        }
      } catch (_) {}
    }
    final sites = trimmed
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return (sites: sites, apps: <Map<String, String>>[], keywords: <String>[]);
  }

  static Future<Map<String, dynamic>> _buildFocusEnvelope(FocusFiltersDto f) async {
    bool antiCheatActive = false;
    String antiCheatMode = 'OFF';
    try {
      final antiCheat = await getAntiCheatState();
      antiCheatActive = antiCheat.isActive;
      antiCheatMode = antiCheat.mode;
    } catch (_) {}
    String primaryLang = 'pt-BR';
    try {
      primaryLang = await getPrimaryLanguage();
    } catch (_) {}
    final tagDisplayMap = <String, String>{};
    if (f.launcherBlockedTags.isNotEmpty) {
      try {
        final entries = await getTagDisplayMap(
          tags: f.launcherBlockedTags,
          lang: primaryLang,
        );
        for (final entry in entries) {
          tagDisplayMap[entry.canonicalEn] = entry.displayName;
        }
      } catch (_) {}
    }
    return {
      'revision': _computeFiltersRevision(
        f,
        antiCheatActive: antiCheatActive,
        antiCheatMode: antiCheatMode,
      ),
      'stateRevision': _filtersRevision,
      'antiCheatActive': antiCheatActive,
      'antiCheatMode': antiCheatMode,
      'primaryLanguage': primaryLang,
      'steamLanguage': primaryLang == 'en-US' ? 'english' : 'brazilian',
      'tagDisplayMap': tagDisplayMap,
      'focusFilters': _filtersToMap(f),
    };
  }

  static Future<void> _handleApiStatus(HttpRequest request, HttpResponse res) async {
    final activeUrl = request.uri.queryParameters['activeUrl'] ?? '';
    final activeTitle = request.uri.queryParameters['activeTitle'] ?? '';
    final audibleUrl = request.uri.queryParameters['audibleUrl'] ?? '';
    final audibleTitle = request.uri.queryParameters['audibleTitle'] ?? '';
    if (activeUrl.isNotEmpty || audibleUrl.isNotEmpty) {
      _recordActiveBrowserTab(
        activeUrl,
        activeTitle,
        audibleUrl: audibleUrl,
        audibleTitle: audibleTitle,
      );
    } else {
      _clearActiveBrowserTab();
    }

    final sites = await getAllSiteRulesStatus();
    final list = sites.map((s) {
      final parsed = _parseGroupPatternDetails(s.pattern);
      return {
        'entityId': s.entityId,
        'displayName': s.displayName,
        'targetType': s.targetType,
        'pattern': s.pattern,
        'groupSites': parsed.sites,
        'groupApps': parsed.apps,
        'groupKeywords': parsed.keywords,
        'dailyQuotaSeconds': s.dailyQuotaSeconds,
        'consumedSeconds': s.consumedSeconds,
        'remainingSeconds': s.remainingSeconds,
        'isBlocked': s.isBlocked,
        'emergencyTokensRemaining': s.emergencyTokensRemaining,
        'isWeekend': s.isWeekend,
        'weekendQuotaSeconds': s.weekendQuotaSeconds,
      };
    }).toList();

    FocusFiltersDto focusFilters;
    try {
      focusFilters = await getFocusFilters();
    } catch (_) {
      focusFilters = _defaultFocusFilters;
    }

    bool antiCheatActive = false;
    String antiCheatMode = 'OFF';
    try {
      final antiCheat = await getAntiCheatState();
      antiCheatActive = antiCheat.isActive;
      antiCheatMode = antiCheat.mode;
    } catch (_) {}

    final envelope = await _buildFocusEnvelope(focusFilters);
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({
      'online': true,
      'port': _port,
      'serverVersion': '1.2.0',
      ...envelope,
      'antiCheatActive': antiCheatActive,
      'antiCheatMode': antiCheatMode,
      'sites': list,
    }));
    await res.close();
  }

  static Future<void> _handleProxyPac(HttpResponse res) async {
    res.headers.set('Content-Type', 'application/x-ns-proxy-autoconfig; charset=utf-8');
    res.headers.set('Cache-Control', 'no-store');
    res.write(buildProxyPacContent());
    await res.close();
  }

  static Future<void> _handleFocusFilters(HttpRequest request, HttpResponse res) async {
    if (request.method == 'GET') {
      FocusFiltersDto filters;
      try {
        filters = await getFocusFilters();
      } catch (_) {
        filters = _defaultFocusFilters;
      }
      final envelope = await _buildFocusEnvelope(filters);
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'success': true,
        ...envelope,
      }));
      await res.close();
      return;
    }

    if (request.method == 'POST') {
      try {
        final bodyStr = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(bodyStr);
        if (decoded is Map<String, dynamic>) {
          final reqLang = decoded['primaryLanguage'] ?? decoded['language'];
          if (reqLang is String && reqLang.trim().isNotEmpty) {
            try {
              await setPrimaryLanguage(lang: reqLang.trim());
            } catch (_) {}
          }
          FocusFiltersDto current;
          try {
            current = await getFocusFilters();
          } catch (_) {
            current = _defaultFocusFilters;
          }
          final nextGrayscale = decoded['globalGrayscale'] is bool
              ? decoded['globalGrayscale'] as bool
              : (decoded['grayscaleMode'] is bool
                  ? decoded['grayscaleMode'] as bool
                  : current.globalGrayscale);
          final nextNotifications = decoded['globalBlockNotifications'] is bool
              ? decoded['globalBlockNotifications'] as bool
              : (decoded['blockNotifications'] is bool
                  ? decoded['blockNotifications'] as bool
                  : current.globalBlockNotifications);
          final nextHudAlpha = decoded['hudAlpha'] is num
              ? (decoded['hudAlpha'] as num).toDouble().clamp(0.15, 1.0)
              : current.hudAlpha;
          final nextHudHideToEye = decoded['hudHideToEye'] is bool
              ? decoded['hudHideToEye'] as bool
              : current.hudHideToEye;
          final nextHudScale = decoded['hudScale'] is num
              ? (decoded['hudScale'] as num).toDouble().clamp(0.70, 1.60)
              : (decoded['hud_scale'] is num
                  ? (decoded['hud_scale'] as num).toDouble().clamp(0.70, 1.60)
                  : current.hudScale);
          final nextLauncherEnabled = decoded['launcherFilterEnabled'] is bool
              ? decoded['launcherFilterEnabled'] as bool
              : (decoded['launcher_filter_enabled'] is bool
                  ? decoded['launcher_filter_enabled'] as bool
                  : current.launcherFilterEnabled);
          final nextLauncherTags = decoded.containsKey('launcherBlockedTags')
              ? _parseStringListField(decoded['launcherBlockedTags'])
              : (decoded.containsKey('launcher_blocked_tags')
                  ? _parseStringListField(decoded['launcher_blocked_tags'])
                  : current.launcherBlockedTags);
          final nextLauncherNames = decoded.containsKey('launcherBlockedNames')
              ? _parseStringListField(decoded['launcherBlockedNames'])
              : (decoded.containsKey('launcher_blocked_names')
                  ? _parseStringListField(decoded['launcher_blocked_names'])
                  : current.launcherBlockedNames);
          final updated = FocusFiltersDto(
            blockShorts: false,
            grayscaleMode: nextGrayscale,
            educationalOnly: false,
            blockFeed: false,
            blockComments: false,
            blockNotifications: nextNotifications,

            ytBlockShorts: decoded['ytBlockShorts'] is bool ? decoded['ytBlockShorts'] : current.ytBlockShorts,
            ytEducationalMode: decoded['ytEducationalMode'] is bool ? decoded['ytEducationalMode'] : current.ytEducationalMode,
            ytBlockSidebar: decoded['ytBlockSidebar'] is bool ? decoded['ytBlockSidebar'] : current.ytBlockSidebar,
            ytBlockComments: decoded['ytBlockComments'] is bool ? decoded['ytBlockComments'] : current.ytBlockComments,

            igBlockReels: decoded['igBlockReels'] is bool ? decoded['igBlockReels'] : current.igBlockReels,
            igBlockFeed: decoded['igBlockFeed'] is bool ? decoded['igBlockFeed'] : current.igBlockFeed,
            igBlockComments: decoded['igBlockComments'] is bool ? decoded['igBlockComments'] : current.igBlockComments,

            ttBlockFeed: decoded['ttBlockFeed'] is bool ? decoded['ttBlockFeed'] : current.ttBlockFeed,

            rdBlockFeed: decoded['rdBlockFeed'] is bool ? decoded['rdBlockFeed'] : current.rdBlockFeed,
            rdBlockComments: decoded['rdBlockComments'] is bool ? decoded['rdBlockComments'] : current.rdBlockComments,

            twBlockFeed: decoded['twBlockFeed'] is bool ? decoded['twBlockFeed'] : current.twBlockFeed,
            twBlockTrends: decoded['twBlockTrends'] is bool ? decoded['twBlockTrends'] : current.twBlockTrends,

            liBlockFeed: decoded['liBlockFeed'] is bool ? decoded['liBlockFeed'] : current.liBlockFeed,

            globalGrayscale: nextGrayscale,
            globalBlockNotifications: nextNotifications,

            hudAlpha: nextHudAlpha,
            hudHideToEye: nextHudHideToEye,
            hudScale: nextHudScale,
            launcherFilterEnabled: nextLauncherEnabled,
            launcherBlockedTags: nextLauncherTags,
            launcherBlockedNames: nextLauncherNames,
          );
          final action = await setFocusFilters(filters: updated);
          FocusFiltersDto finalFilters = updated;
          bool antiCheatLocked = false;
          if (!action.success) {
            try {
              final ac = await getAntiCheatState();
              antiCheatLocked = ac.isActive;
              finalFilters = await getFocusFilters();
            } catch (_) {}
          } else {
            nudgeObservers();
          }
          if (antiCheatLocked) {
            res.statusCode = HttpStatus.forbidden;
          }
          final envelope = await _buildFocusEnvelope(finalFilters);
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'success': action.success,
            'antiCheatLocked': antiCheatLocked,
            'message': action.message,
            ...envelope,
          }));
          await res.close();
          return;
        }
      } catch (err) {
        res.statusCode = HttpStatus.badRequest;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'error': err.toString()}));
        await res.close();
        return;
      }
    }

    res.statusCode = HttpStatus.methodNotAllowed;
    await res.close();
  }

  static Future<void> _handleLanguage(HttpRequest request, HttpResponse res) async {
    if (request.method == 'POST') {
      try {
        final bodyStr = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(bodyStr);
        final reqLang = decoded is Map
            ? (decoded['primaryLanguage'] ?? decoded['language'] ?? 'pt-BR').toString()
            : 'pt-BR';
        final action = await setPrimaryLanguage(lang: reqLang);
        nudgeObservers();
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'success': action.success,
          'primaryLanguage': action.message,
          'stateRevision': _filtersRevision,
        }));
      } catch (err) {
        res.statusCode = HttpStatus.badRequest;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'success': false, 'error': err.toString()}));
      }
      await res.close();
      return;
    }
    String primaryLang = 'pt-BR';
    try {
      primaryLang = await getPrimaryLanguage();
    } catch (_) {}
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({
      'success': true,
      'primaryLanguage': primaryLang,
      'steamLanguage': primaryLang == 'en-US' ? 'english' : 'brazilian',
    }));
    await res.close();
  }

  static Future<void> _handleEvents(HttpResponse res) async {
    res.bufferOutput = false;
    res.headers.set('Content-Type', 'text/event-stream; charset=utf-8');
    res.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.headers.set('Connection', 'keep-alive');

    Future<bool> emitUpdate() async {
      try {
        final f = await getFocusFilters();
        final envelope = await _buildFocusEnvelope(f);
        res.write('event: chronos_update\ndata: ${jsonEncode(envelope)}\n\n');
        await res.flush();
        return true;
      } catch (_) {
        return false;
      }
    }

    if (!await emitUpdate()) {
      try {
        await res.close();
      } catch (_) {}
      return;
    }

    final completer = Completer<void>();
    late final StreamSubscription<int> sub;
    late final Timer keepalive;
    void finish() {
      sub.cancel();
      keepalive.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    sub = _sseController.stream.listen((_) async {
      if (!await emitUpdate()) finish();
    });
    keepalive = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        res.write(': keepalive\n\n');
        await res.flush();
      } catch (_) {
        finish();
      }
    });
    unawaited(res.done.whenComplete(finish));
    await completer.future;
  }

  static Future<void> _handleLaunchersTags(HttpRequest request, HttpResponse res) async {
    final reqLang = request.uri.queryParameters['lang'];
    String primaryLang = reqLang?.trim().isNotEmpty == true ? reqLang!.trim() : 'pt-BR';
    if (reqLang == null || reqLang.trim().isEmpty) {
      try {
        primaryLang = await getPrimaryLanguage();
      } catch (_) {}
    }
    List<SteamTagSuggestionDto> items = const <SteamTagSuggestionDto>[];
    try {
      items = await getPopularSteamTagsLocalized(lang: primaryLang);
    } catch (_) {}
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({
      'success': true,
      'primaryLanguage': primaryLang,
      'steamLanguage': primaryLang == 'en-US' ? 'english' : 'brazilian',
      'tags': items.map((t) => t.displayName).toList(),
      'tagItems': items
          .map((t) => {
                'tagId': t.tagId,
                'canonicalEn': t.canonicalEn,
                'displayName': t.displayName,
              })
          .toList(),
    }));
    await res.close();
  }

  static Future<void> _handleLaunchersAutocomplete(HttpRequest request, HttpResponse res) async {
    final kind = (request.uri.queryParameters['kind'] ?? 'tag').trim().toLowerCase();
    final q = request.uri.queryParameters['q'] ?? '';
    final reqLang = request.uri.queryParameters['lang'];
    String primaryLang = reqLang?.trim().isNotEmpty == true ? reqLang!.trim() : 'pt-BR';
    if (reqLang == null || reqLang.trim().isEmpty) {
      try {
        primaryLang = await getPrimaryLanguage();
      } catch (_) {}
    }
    res.headers.contentType = ContentType.json;
    if (kind == 'game' || kind == 'games') {
      final results = await searchSteamGamesAutocomplete(query: q, lang: primaryLang);
      res.write(jsonEncode({
        'success': true,
        'kind': 'game',
        'primaryLanguage': primaryLang,
        'results': results
            .map((g) => {
                  'appId': g.appId,
                  'title': g.title,
                  'tinyImage': g.tinyImage,
                  'source': g.source,
                })
            .toList(),
      }));
    } else {
      final results = await searchSteamTagsAutocomplete(query: q, lang: primaryLang);
      res.write(jsonEncode({
        'success': true,
        'kind': 'tag',
        'primaryLanguage': primaryLang,
        'results': results
            .map((t) => {
                  'tagId': t.tagId,
                  'canonicalEn': t.canonicalEn,
                  'displayName': t.displayName,
                })
            .toList(),
      }));
    }
    await res.close();
  }

  static Future<void> _handleLaunchersResolve(HttpRequest request, HttpResponse res) async {
    if (request.method != 'POST') {
      res.statusCode = HttpStatus.methodNotAllowed;
      await res.close();
      return;
    }
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(bodyStr);
      final rawItems = (decoded is Map && decoded['items'] is List)
          ? (decoded['items'] as List)
          : const [];
      FocusFiltersDto filters;
      try {
        filters = await getFocusFilters();
      } catch (_) {
        filters = _defaultFocusFilters;
      }
      final hasRules = filters.launcherFilterEnabled &&
          (filters.launcherBlockedTags.isNotEmpty || filters.launcherBlockedNames.isNotEmpty);
      final forceLookup = decoded is Map && decoded['forceLookup'] == true;

      final results = <Map<String, dynamic>>[];
      var lookups = 0;
      for (var i = 0; i < rawItems.length && i < 120; i++) {
        final item = rawItems[i];
        if (item is! Map) continue;
        final id = (item['id'] ?? i).toString();
        final url = (item['url'] ?? '').toString();
        final title = (item['title'] ?? '').toString().trim();
        final appId = (item['appId'] is num)
            ? (item['appId'] as num).toInt()
            : _extractSteamAppIdFromUrl(url);
        final siteTags = _parseStringListField(item['siteTags']);

        LauncherGameDto? meta;
        if ((hasRules || forceLookup) && (appId != null || (title.isNotEmpty && lookups < 6))) {
          if (appId == null) lookups++;
          try {
            meta = await lookupSteamGameMetadata(query: title, appId: appId);
          } catch (_) {}
        }

        final displayTitle = (meta != null && meta.title.trim().isNotEmpty) ? meta.title : title;
        final allTerms = <String>{
          ...siteTags,
          if (meta != null) ...meta.tags,
          if (meta != null) ...meta.genres,
          if (meta != null) ...meta.categories,
        }.toList();

        String? matchType;
        String? matchedTerm;
        String reason = '';
        if (filters.launcherFilterEnabled) {
          final normTitle = _normalizeLauncherText(displayTitle);
          final compactTitle = normTitle.replaceAll(RegExp(r'[^a-z0-9]'), '');
          for (final bn in filters.launcherBlockedNames) {
            final nn = _normalizeLauncherText(bn);
            final nc = nn.replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (nn.isNotEmpty &&
                (normTitle.contains(nn) || (nc.length >= 3 && compactTitle.contains(nc)))) {
              matchType = 'NOME';
              matchedTerm = bn;
              reason = 'Bloqueado pelo filtro de nome "$bn"';
              break;
            }
          }
          if (matchType == null) {
            final normTerms = allTerms.map(_normalizeLauncherText).toList();
            for (final bt in filters.launcherBlockedTags) {
              final nt = _normalizeLauncherText(bt);
              final ct = nt.replaceAll(RegExp(r'[^a-z0-9]'), '');
              final umbrella = _isUmbrellaAdultTag(nt);
              final hit = normTerms.any((c) {
                if (c == nt) return true;
                if (umbrella && _isExplicitAdultTagCandidate(c)) return true;
                final cc = c.replaceAll(RegExp(r'[^a-z0-9]'), '');
                return ct.length >= 3 && (cc == ct || (c.contains(nt) && nt.length >= 4));
              });
              if (hit) {
                matchType = 'TAG';
                matchedTerm = bt;
                final sourceLabel = (meta != null && meta.launcher.trim().isNotEmpty)
                    ? meta.launcher.trim()
                    : 'Página';
                reason = 'Bloqueado pela tag "$bt" ($sourceLabel)';
                break;
              }
            }
          }
        }

        results.add({
          'id': id,
          'appId': meta?.appId ?? appId,
          'title': displayTitle,
          'tags': allTerms,
          'blocked': matchType != null,
          'matchType': matchType,
          'matchedTerm': matchedTerm,
          'reason': reason,
        });
      }

      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'success': true,
        'filterEnabled': filters.launcherFilterEnabled,
        'results': results,
      }));
      await res.close();
    } catch (err) {
      res.statusCode = HttpStatus.badRequest;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': false, 'error': err.toString()}));
      await res.close();
    }
  }

  static List<String> _extractPatternsFromJsonOrCsv(String raw, {String fallbackId = '', String targetType = 'SITE'}) {
    final patterns = <String>[];
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          if (decoded['sites'] is List) {
            for (final item in decoded['sites']) {
              if (item is String && item.trim().isNotEmpty) {
                patterns.add(item.trim().toLowerCase());
              }
            }
          }
          if (decoded['apps'] is List) {
            for (final item in decoded['apps']) {
              final candidates = <String>[];
              if (item is String && item.trim().isNotEmpty) {
                candidates.add(item.trim().toLowerCase());
              } else if (item is Map) {
                final name = item['name']?.toString().trim().toLowerCase() ?? '';
                final exec = item['exec']?.toString().trim().toLowerCase() ?? '';
                if (name.isNotEmpty) candidates.add(name);
                if (exec.isNotEmpty) candidates.add(exec);
              }
              for (final appName in candidates) {
                patterns.add(appName);
                for (final entry in _knownAppDomains.entries) {
                  if (appName.contains(entry.key)) {
                    patterns.addAll(entry.value);
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    } else {
      patterns.addAll(
        trimmed.split(',').map((p) => p.trim().toLowerCase()).where((p) => p.isNotEmpty),
      );
    }

    final typeUpper = targetType.toUpperCase();
    if (patterns.isEmpty &&
        fallbackId.isNotEmpty &&
        (typeUpper == 'SITE' || typeUpper == 'KEYWORD' || typeUpper == 'SITE_GROUP')) {
      patterns.add(fallbackId.toLowerCase());
    }
    return patterns;
  }

  static Future<void> _handleApiCheck(HttpRequest request, HttpResponse res) async {
    final urlParam = request.uri.queryParameters['url'] ?? '';
    final domainParam = request.uri.queryParameters['domain'] ?? '';
    final titleParam = request.uri.queryParameters['title'] ?? '';
    final target = (urlParam.isNotEmpty ? urlParam : domainParam).toLowerCase();
    final titleLower = titleParam.toLowerCase();

    if (urlParam.isNotEmpty) {
      _recordActiveBrowserTab(urlParam, titleParam);
    }

    // 1. Checa Whitelist primeiro
    try {
      final whitelistGroups = await getAllWhitelistGroups();
      bool isWhitelisted = false;
      for (final wg in whitelistGroups) {
        final items = _extractPatternsFromJsonOrCsv(wg.items, targetType: 'GROUP');
        for (final item in items) {
          if (target.contains(item) || (titleLower.isNotEmpty && titleLower.contains(item))) {
            isWhitelisted = true;
            break;
          }
        }
        if (isWhitelisted) break;
      }

      if (isWhitelisted) {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'blocked': false, 'whitelisted': true}));
        await res.close();
        return;
      }
    } catch (_) {}

    final sites = await getAllSiteRulesStatus();
    SiteStatusDto? matched;

    for (final s in sites) {
      final type = s.targetType.toUpperCase();
      // Suporta GROUP (unificado), SITE_GROUP, SITE e KEYWORD
      if (type != 'SITE' && type != 'KEYWORD' && type != 'SITE_GROUP' && type != 'GROUP') continue;

      final patterns = _extractPatternsFromJsonOrCsv(
        s.pattern,
        fallbackId: s.entityId,
        targetType: type,
      );

      for (final p in patterns) {
        if (target.contains(p) || (titleLower.isNotEmpty && titleLower.contains(p))) {
          matched = s;
          break;
        }
      }
      if (matched != null) break;
    }

    res.headers.contentType = ContentType.json;
    if (matched != null) {
      res.write(jsonEncode({
        'blocked': matched.isBlocked,
        'entityId': matched.entityId,
        'displayName': matched.displayName,
        'remainingSeconds': matched.remainingSeconds,
        'dailyQuotaSeconds': matched.dailyQuotaSeconds,
        'emergencyTokensRemaining': matched.emergencyTokensRemaining,
        'targetType': matched.targetType,
      }));
    } else {
      res.write(jsonEncode({
        'blocked': false,
        'matched': false,
      }));
    }
    await res.close();
  }

  static Future<void> _handleEmergencyToken(HttpRequest request, HttpResponse res) async {
    String entityId = request.uri.queryParameters['entityId'] ?? '';

    if (entityId.isEmpty) {
      final bodyStr = await utf8.decodeStream(request);
      if (bodyStr.isNotEmpty) {
        try {
          final json = jsonDecode(bodyStr);
          if (json is Map && json['entityId'] != null) {
            entityId = json['entityId'].toString();
          }
        } catch (_) {}
      }
    }

    if (entityId.isEmpty) {
      res.statusCode = HttpStatus.badRequest;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': false, 'message': 'entityId é obrigatório.'}));
      await res.close();
      return;
    }

    final feedback = await consumeEmergencyToken(entityId: entityId);
    if (feedback.success) {
      nudgeObservers();
    }
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({
      'success': feedback.success,
      'message': feedback.message,
    }));
    await res.close();
  }

  static Future<void> _handleBlockedPage(HttpRequest request, HttpResponse res) async {
    final query = request.uri.queryParameters;
    final entityId = query['entity'] ?? '';
    final site = query['site'] ?? '';
    final originalUrl = query['url'] ?? '';
    final customReason = (query['reason'] ?? '').trim();

    final sites = await getAllSiteRulesStatus();
    SiteStatusDto? currentRule;

    if (entityId != 'launcher_filter' && entityId.isNotEmpty) {
      currentRule = sites.cast<SiteStatusDto?>().firstWhere(
        (s) => s?.entityId.toLowerCase() == entityId.toLowerCase(),
        orElse: () => null,
      );
    }

    if (entityId != 'launcher_filter' && currentRule == null && site.isNotEmpty) {
      final siteLower = site.toLowerCase();
      currentRule = sites.cast<SiteStatusDto?>().firstWhere(
        (s) {
          if (s == null) return false;
          final pats = _extractPatternsFromJsonOrCsv(
            s.pattern,
            fallbackId: s.entityId,
            targetType: s.targetType,
          );
          return pats.any((p) => siteLower.contains(p)) || siteLower.contains(s.entityId.toLowerCase());
        },
        orElse: () => null,
      );
    }

    final displayName = currentRule?.displayName ??
        (site.isNotEmpty
            ? site
            : (entityId.isNotEmpty && entityId != 'launcher_filter'
                ? entityId
                : 'Jogo / Conteúdo Filtrado'));
    final activeEntityId = currentRule?.entityId ?? (entityId.isNotEmpty ? entityId : 'youtube');
    final isLauncherBlock = entityId == 'launcher_filter' || customReason.isNotEmpty;
    final dailyQuota = isLauncherBlock
        ? 'Filtro de Conteúdo (Steam API / Launchers)'
        : (currentRule != null ? _formatMinutes(currentRule.dailyQuotaSeconds) : 'Limite diário');
    final tokensLeft = currentRule?.emergencyTokensRemaining ?? 2;

    final html = _generateBlockedHtml(
      displayName: displayName,
      entityId: activeEntityId,
      site: site.isNotEmpty ? site : displayName,
      originalUrl: originalUrl,
      dailyQuotaText: dailyQuota,
      emergencyTokens: tokensLeft,
      customReason: customReason,
    );

    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType.html;
    res.write(html);
    await res.close();
  }

  static String _escapeHtml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _formatMinutes(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m > 0 ? '${m}m' : ''}';
    }
    return '${m}m';
  }

  static String _generateBlockedHtml({
    required String displayName,
    required String entityId,
    required String site,
    required String originalUrl,
    required String dailyQuotaText,
    required int emergencyTokens,
    String customReason = '',
  }) {
    final safeDisplayName = _escapeHtml(displayName);
    final safeDailyQuota = _escapeHtml(dailyQuotaText);
    final safeReason = _escapeHtml(customReason);
    final isLauncherBlock = entityId == 'launcher_filter' || customReason.isNotEmpty;
    final badgeLabel = isLauncherBlock ? 'Filtro de Jogos &amp; Launchers' : 'Limite de Tempo Esgotado';
    final headlineLabel = isLauncherBlock ? 'Conteúdo de Jogo Bloqueado' : 'Site Indisponível';
    final msgHtml = isLauncherBlock
        ? 'O conteúdo <span class="site-target">$safeDisplayName</span> (loja, página do jogo, guias, discussões ou artworks) foi bloqueado: <strong>${safeReason.isNotEmpty ? safeReason : 'Filtro de launcher ativo'}</strong>.'
        : 'O site <span class="site-target">$safeDisplayName</span> não está disponível pois o seu tempo de tela diário acabou.';
    return '''<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Site Indisponível - Chronos</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background: radial-gradient(circle at 50% 20%, #1a1e24 0%, #0d1117 80%, #080a0d 100%);
      color: #e6edf3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
      line-height: 1.5;
    }
    .container {
      max-width: 620px;
      width: 100%;
      background: rgba(22, 27, 34, 0.85);
      border: 1px solid rgba(248, 81, 73, 0.35);
      border-radius: 20px;
      padding: 44px 36px;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6), 0 0 40px rgba(248, 81, 73, 0.12);
      backdrop-filter: blur(12px);
      animation: fadeIn 0.4s ease-out;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(16px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .icon-box {
      width: 90px;
      height: 90px;
      margin: 0 auto 24px;
      background: rgba(248, 81, 73, 0.12);
      border: 2px solid #f85149;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 30px rgba(248, 81, 73, 0.25);
    }
    .icon-box svg {
      width: 48px;
      height: 48px;
      fill: #f85149;
    }
    .badge {
      display: inline-block;
      background: rgba(248, 81, 73, 0.2);
      color: #ff7b72;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 1.2px;
      text-transform: uppercase;
      padding: 6px 14px;
      border-radius: 20px;
      border: 1px solid rgba(248, 81, 73, 0.4);
      margin-bottom: 16px;
    }
    h1 {
      font-size: 28px;
      font-weight: 800;
      color: #ffffff;
      margin-bottom: 12px;
      letter-spacing: -0.5px;
    }
    .site-target {
      color: #f85149;
      font-weight: 800;
    }
    p.message {
      font-size: 16px;
      color: #8b949e;
      margin-bottom: 28px;
    }
    .card-info {
      background: rgba(13, 17, 23, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 14px;
      padding: 18px 20px;
      margin-bottom: 28px;
      text-align: left;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.05);
      font-size: 14px;
    }
    .info-row:last-child {
      border-bottom: none;
    }
    .info-label {
      color: #8b949e;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .info-value {
      font-weight: 600;
      color: #e6edf3;
    }
    .token-section {
      background: rgba(210, 153, 34, 0.1);
      border: 1px solid rgba(210, 153, 34, 0.3);
      border-radius: 14px;
      padding: 18px 20px;
      margin-bottom: 26px;
    }
    .token-text {
      font-size: 14px;
      color: #d29922;
      margin-bottom: 12px;
      font-weight: 500;
    }
    .btn-token {
      background: linear-gradient(135deg, #d29922 0%, #b07d12 100%);
      color: #000000;
      font-size: 14px;
      font-weight: 700;
      border: none;
      padding: 12px 24px;
      border-radius: 10px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      transition: all 0.2s ease;
      box-shadow: 0 4px 14px rgba(210, 153, 34, 0.3);
    }
    .btn-token:hover:not(:disabled) {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(210, 153, 34, 0.45);
      filter: brightness(1.1);
    }
    .btn-token:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }
    .quote-box {
      font-style: italic;
      font-size: 13px;
      color: #58a6ff;
      margin-top: 10px;
    }
    .footer {
      margin-top: 24px;
      font-size: 12px;
      color: #484f58;
    }
    .status-msg {
      margin-top: 10px;
      font-size: 13px;
      font-weight: 600;
      display: none;
    }
  </style>
</head>
<body>

  <div class="container">
    <div class="icon-box">
      <!-- Shield / Hourglass Icon -->
      <svg viewBox="0 0 24 24">
        <path d="M12 2L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-3zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-2.33v8.02z"/>
      </svg>
    </div>

    <div class="badge">$badgeLabel</div>
    <h1>$headlineLabel</h1>
    <p class="message">
      $msgHtml
    </p>

    <div class="card-info">
      <div class="info-row">
        <span class="info-label">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="#8b949e"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg>
          ${isLauncherBlock ? 'Regra ativa:' : 'Tempo de tela diário configurado:'}
        </span>
        <span class="info-value">$safeDailyQuota</span>
      </div>
      ${isLauncherBlock ? '' : '''<div class="info-row">
        <span class="info-label">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="#8b949e"><path d="M18 1c-2.76 0-5 2.24-5 5v2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2h-1V6c0-2.76-2.24-5-5-5zm0 2c1.66 0 3 1.34 3 3v2h-6V6c0-1.66 1.34-3 3-3zm-6 12.72V17h2v-1.28c.6-.35 1-.99 1-1.72 0-1.1-.9-2-2-2s-2 .9-2 2c0 .73.4 1.37 1 1.72z"/></svg>
          Próxima liberação:
        </span>
        <span class="info-value">Amanhã à meia-noite (00:00)</span>
      </div>'''}
      <div class="info-row">
        <span class="info-label">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="#8b949e"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-3z"/></svg>
          Status de segurança:
        </span>
        <span class="info-value" style="color: #3fb950;">Bloqueio Ativo pelo Chronos</span>
      </div>
    </div>

    ${isLauncherBlock ? '''
    <div class="token-section" style="border-color: rgba(255,255,255,0.1); background: rgba(255,255,255,0.03);">
      <div class="token-text" style="color: #8b949e; margin-bottom: 0;">
        Para liberar este conteúdo, remova a tag ou nome correspondente nas configurações de <strong>Launchers &amp; Jogos</strong> (Anti-Cheat deve estar desativado).
      </div>
    </div>
    ''' : (emergencyTokens > 0 ? '''
    <div class="token-section">
      <div class="token-text">
        Você possui <strong>$emergencyTokens token(s)</strong> de emergência disponíveis este mês.
      </div>
      <button id="btn-token" class="btn-token" onclick="consumeToken('$entityId')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42A6.92 6.92 0 0 1 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.05.88-3.9 2.29-5.18L5.87 5.4C4.1 6.99 3 9.35 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.65-1.1-5.01-2.87-6.6z"/></svg>
        Usar Token de Emergência (+1h)
      </button>
      <div id="status-msg" class="status-msg"></div>
    </div>
    ''' : '''
    <div class="token-section" style="border-color: rgba(255,255,255,0.1); background: rgba(255,255,255,0.03);">
      <div class="token-text" style="color: #8b949e; margin-bottom: 0;">
        Nenhum token de emergência restante para este mês.
      </div>
    </div>
    ''')}

    <div class="quote-box">
      "O foco no presente constrói a disciplina do amanhã."
    </div>

    <div class="footer">
      Chronos Focus Engine • Offline-first Productivity Guard
    </div>
  </div>

  <script>
    const originalUrl = ${jsonEncode(originalUrl)};
    const entityId = ${jsonEncode(entityId)};
    const displayName = ${jsonEncode(displayName)};
    const isLauncherBlock = ${isLauncherBlock ? 'true' : 'false'};

    async function consumeToken(id) {
      const btn = document.getElementById('btn-token');
      const status = document.getElementById('status-msg');
      if (!btn) return;

      btn.disabled = true;
      btn.innerText = 'Ativando token...';
      if (status) {
        status.style.display = 'block';
        status.style.color = '#d29922';
        status.innerText = 'Processando liberação de emergência...';
      }

      try {
        const resp = await fetch('/api/emergency-token?entityId=' + encodeURIComponent(id), {
          method: 'POST'
        });
        const data = await resp.json();

        if (data.success) {
          if (status) {
            status.style.color = '#3fb950';
            status.innerText = '✓ Token ativado com sucesso! +1h concedida. Retornando ao site...';
          }
          setTimeout(() => {
            if (originalUrl && originalUrl.startsWith('http')) {
              window.location.href = originalUrl;
            } else {
              window.location.reload();
            }
          }, 1500);
        } else {
          btn.disabled = false;
          btn.innerText = 'Usar Token de Emergência (+1h)';
          if (status) {
            status.style.color = '#f85149';
            status.innerText = data.message || 'Falha ao ativar token.';
          }
        }
      } catch (err) {
        btn.disabled = false;
        btn.innerText = 'Usar Token de Emergência (+1h)';
        if (status) {
          status.style.color = '#f85149';
          status.innerText = 'Erro de conexão com o Chronos Daemon.';
        }
      }
    }

    // Polling a cada 5 segundos: se a regra for desbloqueada no app, recarrega o site original
    setInterval(async () => {
      try {
        if (isLauncherBlock) {
          const res = await fetch('/api/launchers/resolve', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ items: [{ id: 'self', url: originalUrl, title: displayName }] })
          });
          const data = await res.json();
          const item = data && Array.isArray(data.results) ? data.results[0] : null;
          if (item && item.blocked === false && originalUrl && originalUrl.startsWith('http')) {
            window.location.href = originalUrl;
          }
          return;
        }
        const res = await fetch('/api/check?url=' + encodeURIComponent(originalUrl || entityId));
        const data = await res.json();
        if (data && data.blocked === false) {
          if (originalUrl && originalUrl.startsWith('http')) {
            window.location.href = originalUrl;
          }
        }
      } catch (_) {}
    }, 5000);
  </script>
</body>
</html>''';
  }
}
