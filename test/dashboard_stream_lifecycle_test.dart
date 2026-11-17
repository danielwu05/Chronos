import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

void main() {
  group('Dashboard Stream Lifecycle & Re-listening Tests', () {
    test('Proof of Root Cause: Direct re-listening to a single-subscription stream throws Bad state', () async {
      final controller = StreamController<LiveEngineTick>(); // single-subscription
      final stream = controller.stream;

      // First listener connects
      final sub1 = stream.listen((_) {});
      await sub1.cancel();

      // Second listener attempts to connect to the same stream instance
      expect(
        () => stream.listen((_) {}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Stream has already been listened to'),
        )),
      );

      await controller.close();
    });

    test('Fixed Pattern: ValueNotifier + managed StreamSubscription prevents Stream has already been listened to', () async {
      StreamSubscription<LiveEngineTick>? subscription;
      final tickNotifier = ValueNotifier<LiveEngineTick?>(null);
      int receivedTicks = 0;

      // Listener 1 attaches to the ValueNotifier (e.g. Dashboard Tab)
      void listener1() {
        if (tickNotifier.value != null) receivedTicks++;
      }
      tickNotifier.addListener(listener1);

      // Listener 2 attaches concurrently (e.g. FocusBadge in Header)
      tickNotifier.addListener(() {});

      // Simulate stream start 1
      StreamController<LiveEngineTick> streamController1 = StreamController<LiveEngineTick>();
      subscription = streamController1.stream.listen((tick) {
        tickNotifier.value = tick;
      });

      const tickA = LiveEngineTick(
        entityId: 'youtube',
        displayName: 'YouTube',
        remainingSeconds: 1800,
        dailyQuotaSeconds: 3600,
        consumedSeconds: 1800,
        isActiveNow: true,
        isBackgroundPlayback: false,
        isBlocked: false,
        detectedActivityLabel: 'Vídeo Ativo',
        ratchetLockedUntilUtc: null,
        emergencyTokensRemaining: 2,
        leisureLockedUntilUtc: 0,
        targetType: 'SITE',
        isWeekend: false,
        weekendQuotaSeconds: null,
        activeSessionsJson: '[]',
      );

      streamController1.add(tickA);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tickNotifier.value, equals(tickA));
      expect(receivedTicks, equals(1));

      // Simulate tab switch or screen resize: Listener 1 detaches and re-attaches
      tickNotifier.removeListener(listener1);
      tickNotifier.addListener(listener1);

      // ValueNotifier still holds the latest tick without flickering or re-listening error
      expect(tickNotifier.value, equals(tickA));

      // Simulate stream restart (e.g. switching entity or db reload)
      await subscription.cancel();
      StreamController<LiveEngineTick> streamController2 = StreamController<LiveEngineTick>();
      subscription = streamController2.stream.listen((tick) {
        tickNotifier.value = tick;
      });

      const tickB = LiveEngineTick(
        entityId: 'steam',
        displayName: 'Steam',
        remainingSeconds: 600,
        dailyQuotaSeconds: 3600,
        consumedSeconds: 3000,
        isActiveNow: true,
        isBackgroundPlayback: false,
        isBlocked: false,
        detectedActivityLabel: 'Jogo em Execução',
        ratchetLockedUntilUtc: null,
        emergencyTokensRemaining: 2,
        leisureLockedUntilUtc: 0,
        targetType: 'APP',
        isWeekend: false,
        weekendQuotaSeconds: null,
        activeSessionsJson: '[]',
      );

      streamController2.add(tickB);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tickNotifier.value, equals(tickB));
      expect(receivedTicks, equals(2));

      // Clean cleanup
      await subscription.cancel();
      await streamController1.close();
      await streamController2.close();
      tickNotifier.dispose();
    });
  });
}
