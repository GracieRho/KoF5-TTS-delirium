import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';
import 'playback_trial_setup.dart';

void main() {
  testWidgets('late first play completion cannot stop a newer reply', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform();
    RecordPlatform.instance = fake;
    fake.permission.complete(true);
    final firstPlayStarted = Completer<void>();
    final firstPlayResult = Completer<void>();
    var plays = 0;
    var stops = 0;
    const channel = MethodChannel('kof5/trial_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play') {
        plays++;
        if (plays == 1) {
          firstPlayStarted.complete();
          await firstPlayResult.future;
        }
        return null;
      }
      if (call.method == 'stop') {
        stops++;
        return null;
      }
      throw PlatformException(code: 'unknown');
    });
    SyntheticCloudReply reply() =>
        SyntheticCloudReply('수민아?', '응, 왜?', Uint8List.fromList([1, 2, 3]));
    try {
      await startMockPlaybackTrial(
        tester,
        fake,
        (_, _, _, _) async => reply(),
      );
      await tester.runAsync(
        () => firstPlayStarted.future.timeout(const Duration(seconds: 2)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('마이크 시험 시작'));
      await tester.tap(find.text('마이크 시험 시작'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(fake.starts, 2);
      fake.feedCandidate();
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/internal/synthetic/audio',
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 32);
      final upload = find.widgetWithText(FilledButton, '자가 음성 후보 한 건 보내기');
      expect(tester.widget<FilledButton>(upload).onPressed, isNotNull);
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      for (var index = 0; index < 20 && plays < 2; index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(plays, 2);
      final stopsBeforeOldCompletion = stops;
      firstPlayResult.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(stops, stopsBeforeOldCompletion);
      expect(find.text('음성 응답 중단'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      RecordPlatform.instance = original;
    }
  });
}
