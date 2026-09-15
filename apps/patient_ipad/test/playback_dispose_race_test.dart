import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';
import 'playback_trial_setup.dart';

void main() {
  testWidgets(
    'disposing during delayed native play never renders or leaves audio active',
    (tester) async {
      final original = RecordPlatform.instance;
      final fake = FakeRecorderPlatform();
      RecordPlatform.instance = fake;
      fake.permission.complete(true);
      final playStarted = Completer<void>();
      final playResult = Completer<void>();
      var stopCalls = 0;
      const channel = MethodChannel('kof5/trial_audio');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'play') {
          playStarted.complete();
          await playResult.future;
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
          (_, _, _, _) async => SyntheticCloudReply(
            '수민아?',
            '응, 왜?',
            Uint8List.fromList([1, 2, 3]),
          ),
        );
        await tester.runAsync(
          () => playStarted.future.timeout(const Duration(seconds: 2)),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect(
          stopCalls,
          1,
          reason: 'dispose must stop playback before delayed play returns',
        );
        playResult.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(
          stopCalls,
          2,
          reason: 'late play completion must re-confirm native stop',
        );
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        RecordPlatform.instance = original;
      }
    },
  );
}
