import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/on_device_speech.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets('natural duplex finish stops shared mic before idle rearm', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform()..permission.complete(true);
    RecordPlatform.instance = fake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const audioChannel = MethodChannel('kof5/trial_audio');
    final finish = Completer<bool>();
    final lateReply = Completer<SyntheticCloudReply>();
    var textCalls = 0;
    messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
      switch (call.method) {
        case 'available':
        case 'authorize':
          return true;
        case 'transcribe':
          return '수민아?';
        case 'cancel':
          return null;
      }
      throw MissingPluginException();
    });
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      switch (call.method) {
        case 'play':
          expect((call.arguments as Map)['concurrentMic'], true);
          return null;
        case 'waitFinished':
          return finish.future;
        case 'stop':
          return null;
      }
      throw MissingPluginException();
    });
    try {
      await tester.pumpWidget(
        PatientMicDemo(
          textTrial: (client, endpoint, token, transcript, label) async {
            textCalls++;
            if (textCalls == 3) return lateReply.future;
            return SyntheticCloudReply(
              transcript,
              textCalls == 1 ? '응, 왜?' : null,
              textCalls == 1 ? Uint8List.fromList([1, 2, 3]) : null,
            );
          },
        ),
      );
      await tester.tap(find.text('마이크 시험 시작'));
      await _until(tester, () => fake.starts == 1);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _until(
        tester,
        () => find.textContaining('기기 내 전사 준비됨').evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/internal/synthetic/audio',
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 32);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.ensureVisible(find.byType(FilterChip));
      await tester.tap(find.byType(FilterChip));
      fake.feedCandidate();
      await _until(
        tester,
        () => fake.starts == 2 && find.text('음성 응답 중단').evaluate().isNotEmpty,
      );
      expect((textCalls, fake.stops), (1, 1));
      expect(fake.lastConfig?.echoCancel, true);
      finish.complete(true);
      await _until(tester, () => fake.starts == 3);
      expect(
        fake.stops,
        2,
        reason: 'echo-cancelled shared mic stops before next idle mic',
      );
      expect(fake.lastConfig?.echoCancel, false);
      expect(find.text('기기에서 듣고 있습니다'), findsOneWidget);
      fake.feedCandidate();
      await _until(tester, () => textCalls == 2 && fake.starts == 4);
      expect(
        fake.stops,
        3,
        reason: 'null reply returns to confirmed idle listening',
      );
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        textCalls,
        2,
        reason:
            'server refusal pauses proactive text sends, even after mic rearm',
      );
      expect(find.textContaining('자동 글 전송을 중단했습니다'), findsWidgets);
      await tester.ensureVisible(find.text('시험 중단'));
      await tester.tap(find.text('시험 중단'));
      await _until(tester, () => fake.stops == 4);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile));
      await _until(
        tester,
        () => find.textContaining('기기 내 전사 준비됨').evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 32);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('마이크 시험 시작'));
      await tester.tap(find.text('마이크 시험 시작'));
      await _until(tester, () => fake.starts == 5);
      fake.feedCandidate();
      await _until(tester, () => textCalls == 3 && fake.stops == 5);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      lateReply.complete(const SyntheticCloudReply('수민아?', null, null));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        fake.starts,
        5,
        reason: 'withdrawn no-MP3 response cannot restart the microphone',
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      if (!lateReply.isCompleted) {
        lateReply.complete(const SyntheticCloudReply('', null, null));
      }
      if (!finish.isCompleted) finish.complete(false);
      messenger.setMockMethodCallHandler(audioChannel, null);
      messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, null);
      RecordPlatform.instance = original;
    }
  });
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
