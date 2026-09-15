import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';
import 'playback_trial_setup.dart';

void main() {
  testWidgets('failed playback stop remains visible and blocks mic restart', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform();
    RecordPlatform.instance = fake;
    fake.permission.complete(true);
    var failStop = true;
    var stopCalls = 0;
    const channel = MethodChannel('kof5/trial_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play') return null;
      if (call.method == 'stop') {
        stopCalls++;
        if (failStop) throw PlatformException(code: 'stop_failed');
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
      final stop = find.text('음성 응답 중단');
      expect(stop, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.textContaining('음성 응답 중단을 확인하지 못했습니다'), findsOneWidget);
      expect(
        stop,
        findsOneWidget,
        reason: 'stop failure must keep active playback ownership',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.ensureVisible(find.text('마이크 시험 시작'));
      await tester.tap(find.text('마이크 시험 시작'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        fake.starts,
        1,
        reason: 'mic must not restart while playback stop is uncertain',
      );
      expect(stopCalls, greaterThanOrEqualTo(2));

      failStop = false;
      await tester.ensureVisible(stop);
      await tester.tap(stop);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(stop, findsNothing);
      await tester.pumpWidget(const SizedBox());
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      RecordPlatform.instance = original;
    }
  });
}
