import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';
import 'playback_trial_setup.dart';

void main() {
  testWidgets('late play result preserves a newly started local mic', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform();
    RecordPlatform.instance = fake;
    fake.permission.complete(true);
    final firstPlayStarted = Completer<void>();
    final firstPlayResult = Completer<void>();
    var stopCalls = 0;
    const channel = MethodChannel('kof5/trial_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play') {
        firstPlayStarted.complete();
        await firstPlayResult.future;
        return null;
      }
      if (call.method == 'stop') {
        stopCalls++;
        return null;
      }
      throw PlatformException(code: 'unknown');
    });
    try {
      await startMockPlaybackTrial(
        tester,
        fake,
        (_, _, _, _) async =>
            SyntheticCloudReply('수민아?', '응, 왜?', Uint8List.fromList([1, 2, 3])),
      );
      await tester.runAsync(
        () => firstPlayStarted.future.timeout(const Duration(seconds: 2)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(stopCalls, 1);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('마이크 시험 시작'));
      await tester.tap(find.text('마이크 시험 시작'));
      for (var index = 0; index < 20 && fake.starts < 2; index++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(fake.starts, 2);
      firstPlayResult.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        stopCalls,
        2,
        reason: 'old play result rechecks native audio stop',
      );
      fake.feedCandidate();
      await tester.pump();
      final upload = find.widgetWithText(FilledButton, '자가 음성 후보 한 건 보내기');
      expect(
        tester.widget<FilledButton>(upload).onPressed,
        isNotNull,
        reason:
            'late audio cleanup must leave the new mic candidate path usable',
      );
      await tester.ensureVisible(find.text('시험 중단'));
      await tester.tap(find.text('시험 중단'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      RecordPlatform.instance = original;
    }
  });
}
