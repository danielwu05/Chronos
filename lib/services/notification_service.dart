import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Preferências globais de notificação (Configuráveis pela nova aba de Configurações Gerais)
  bool notifyOnAppMonitored = true;
  bool notifyPeriodic = true;
  bool notifyRemaining = true;

  // Track notifications already sent per session to prevent spamming:
  // sessionKey -> Set of threshold keys notified
  final Map<String, Set<String>> _notifiedThresholds = {};
  // sessionKey -> last periodic interval bucket notified
  final Map<String, int> _lastPeriodicBucket = {};
  // sessionKey -> last seen elapsed seconds (to detect daily usage reset)
  final Map<String, int> _lastElapsedSec = {};
  // sessionKey:appName -> rastreador de notificação de abertura do app
  final Set<String> _monitoredNotifiedApps = {};

  /// Sends a desktop notification using notify-send on Linux.
  Future<void> sendNotification({
    required String title,
    required String body,
    String urgency = 'normal', // low, normal, critical
    int expireTimeMs = 5000,
  }) async {
    try {
      final exe = File('/usr/bin/notify-send').existsSync() ? '/usr/bin/notify-send' : 'notify-send';
      await Process.run(exe, [
        '-u',
        urgency,
        '-t',
        expireTimeMs.toString(),
        '-a',
        'Chronos Focus',
        title,
        body,
      ]);
    } catch (_) {
      // Fallback silently if notify-send is unavailable
    }
  }

  /// Notifica que um aplicativo monitorado acabou de entrar em execução
  void notifyAppStartedMonitoring({required String appName, required String sessionName}) {
    if (!notifyOnAppMonitored) return;
    final key = '$sessionName:$appName';
    if (_monitoredNotifiedApps.contains(key)) return;
    _monitoredNotifiedApps.add(key);

    sendNotification(
      title: 'Chronos - Monitoramento Ativo',
      body: 'O aplicativo "$appName" está sendo monitorado na sessão "$sessionName".',
      urgency: 'low',
    );
  }

  void clearMonitoredApp(String sessionName, String appName) {
    _monitoredNotifiedApps.remove('$sessionName:$appName');
  }

  /// Processes active sessions and fires notifications if criteria are met.
  void checkSession(Map<String, dynamic> sessionData) {
    final sessionId = sessionData['entity_id']?.toString() ??
        sessionData['id']?.toString() ??
        sessionData['name']?.toString() ??
        'default';
    final name = sessionData['display_name']?.toString() ??
        sessionData['name']?.toString() ??
        'Sessão';
    final remainingSec = (sessionData['remaining_seconds'] as num?)?.toInt() ??
        (sessionData['remainingSec'] as num?)?.toInt() ??
        0;
    final elapsedSec = (sessionData['consumed_seconds'] as num?)?.toInt() ??
        (sessionData['elapsedSec'] as num?)?.toInt() ??
        0;
    final limitSec = (sessionData['daily_quota_seconds'] as num?)?.toInt() ??
        (sessionData['limitSec'] as num?)?.toInt() ??
        0;
    final notifyMode = sessionData['notify_mode']?.toString() ??
        sessionData['notifyMode']?.toString() ??
        'both';

    // 0. Notifica abertura do app monitorado se configurado
    final detectedApp = sessionData['detected_activity_label']?.toString() ?? '';
    final isActiveNow = sessionData['is_active_now'] == true ||
        sessionData['is_active'] == true ||
        (sessionData['is_active_now'] == null && elapsedSec > 0);
    if (isActiveNow && detectedApp.isNotEmpty && notifyOnAppMonitored) {
      notifyAppStartedMonitoring(appName: detectedApp, sessionName: name);
    } else if (!isActiveNow && detectedApp.isNotEmpty) {
      clearMonitoredApp(name, detectedApp);
    }

    if (notifyMode == 'none') return;

    // Se o consumo foi zerado (reset diário), limpa o histórico de alertas da sessão
    final prevElapsed = _lastElapsedSec[sessionId] ?? 0;
    if (elapsedSec < prevElapsed) {
      resetSession(sessionId);
    }
    _lastElapsedSec[sessionId] = elapsedSec;

    final remainingThresholds = (sessionData['notify_remaining_mins'] as List? ??
                sessionData['notifyRemainingMins'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [15, 5, 1];

    final periodicIntervalMins = ((sessionData['notify_interval_mins'] as num?)?.toInt() ??
            (sessionData['notifyIntervalMins'] as num?)?.toInt() ??
            15)
        .clamp(1, 1440);

    _notifiedThresholds.putIfAbsent(sessionId, () => <String>{});
    final sentKeys = _notifiedThresholds[sessionId]!;

    // 1. Notificações por Tempo Restante
    if (notifyRemaining && (notifyMode == 'remaining' || notifyMode == 'both')) {
      final remainingMins = (remainingSec / 60).ceil();
      for (final threshold in remainingThresholds) {
        final key = 'rem_$threshold';
        if (remainingMins <= threshold && remainingSec > 0 && !sentKeys.contains(key)) {
          sentKeys.add(key);
          final urgency = threshold <= 1 ? 'critical' : 'normal';
          sendNotification(
            title: 'Chronos - Tempo de Tela Restante',
            body: '$name: Restam apenas $threshold minuto${threshold > 1 ? 's' : ''} de tempo de tela!',
            urgency: urgency,
          );
        }
      }

      if (remainingSec <= 0 && limitSec > 0 && !sentKeys.contains('depleted')) {
        sentKeys.add('depleted');
        sendNotification(
          title: 'Chronos - Tempo de Tela Esgotado',
          body: '$name: O tempo de tela diário foi completamente esgotado!',
          urgency: 'critical',
        );
      }
    }

    // 2. Notificações Periódicas (a cada N minutos de uso ativo)
    if (notifyPeriodic && (notifyMode == 'periodic' || notifyMode == 'both')) {
      final intervalSeconds = periodicIntervalMins * 60;
      if (elapsedSec > 0 && intervalSeconds > 0) {
        final currentBucket = elapsedSec ~/ intervalSeconds;
        final prevBucket = _lastPeriodicBucket[sessionId];

        if (prevBucket == null) {
          // Primeira leitura da sessão: se acabou de atingir o múltiplo exato (margem de 2s), notifica
          _lastPeriodicBucket[sessionId] = currentBucket;
          if (currentBucket >= 1 && (elapsedSec % intervalSeconds) <= 2) {
            final elapsedMins = currentBucket * periodicIntervalMins;
            final remMins = (remainingSec / 60).ceil();
            sendNotification(
              title: 'Chronos - Alerta Periódico ($periodicIntervalMins min)',
              body: '$name: $elapsedMins min utilizados hoje • Restam $remMins min de tempo de tela.',
              urgency: 'normal',
            );
          }
        } else if (currentBucket > prevBucket && currentBucket >= 1) {
          _lastPeriodicBucket[sessionId] = currentBucket;
          final elapsedMins = currentBucket * periodicIntervalMins;
          final remMins = (remainingSec / 60).ceil();
          sendNotification(
            title: 'Chronos - Alerta Periódico ($periodicIntervalMins min)',
            body: '$name: $elapsedMins min utilizados hoje • Restam $remMins min de tempo de tela.',
            urgency: 'normal',
          );
        }
      }
    }
  }

  /// Resets tracking for a session (e.g. daily reset or session deletion)
  void resetSession(String sessionId) {
    _notifiedThresholds.remove(sessionId);
    _lastPeriodicBucket.remove(sessionId);
    _lastElapsedSec.remove(sessionId);
  }

  void resetAll() {
    _notifiedThresholds.clear();
    _lastPeriodicBucket.clear();
    _lastElapsedSec.clear();
  }
}
