import 'dart:io';

import 'package:chronos_app/main.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/widgets/focus_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Black Screen & Viewport Regression Tests', () {
    test('resolveBundledRustLibraryPath prefers bundled lib next to executable over CWD target', () {
      final tmpDir = Directory.systemTemp.createTempSync('chronos_bundle_lib_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final fakeExe = File('${tmpDir.path}/chronos_app')..writeAsStringSync('');
      expect(
        resolveBundledRustLibraryPath(
          executablePath: fakeExe.path,
          isLinuxOverride: true,
        ),
        isNull,
      );

      final libDir = Directory('${tmpDir.path}/lib')..createSync(recursive: true);
      final bundledSo = File('${libDir.path}/librust_lib_chronos_app.so')..writeAsBytesSync(const [1, 2, 3]);

      expect(
        resolveBundledRustLibraryPath(
          executablePath: fakeExe.path,
          isLinuxOverride: true,
        ),
        equals(bundledSo.path),
      );
      expect(
        resolveBundledRustLibraryPath(
          executablePath: fakeExe.path,
          isLinuxOverride: false,
        ),
        isNull,
      );
    });

    testWidgets('FocusOverlay renders without overflow on small non-fullscreen viewports', (tester) async {
      final tick = LiveEngineTick(
        entityId: 'group_1',
        displayName: 'Sessão de Foco',
        remainingSeconds: 0,
        dailyQuotaSeconds: 7200,
        consumedSeconds: 7200,
        isActiveNow: true,
        isBackgroundPlayback: false,
        isBlocked: true,
        detectedActivityLabel: 'steam',
        ratchetLockedUntilUtc: null,
        emergencyTokensRemaining: 2,
        leisureLockedUntilUtc: 0,
        targetType: 'GROUP',
        isWeekend: false,
        weekendQuotaSeconds: null,
        activeSessionsJson: '[]',
      );

      for (final size in const [Size(320, 240), Size(592, 641)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FocusOverlay(
                tick: tick,
                onEmergencyTokenUsed: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('ACESSO BLOQUEADO PELO CHRONOS'), findsOneWidget);
      }
    });
  });
}
