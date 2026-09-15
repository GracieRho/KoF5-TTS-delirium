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
  testWidgets('self-voice trial interrupts reply before processing next turn', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform()..permission.complete(true);
    RecordPlatform.instance = fake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const audioChannel = MethodChannel('kof5/trial_audio');
    final finished = Completer<bool>();
    final delayedStop = Completer<void>();
    var transcripts = 0;
    var textCalls = 0;
    var stopCalls = 0;
    messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
      switch (call.method) {
        case 'available':
        case 'authorize':
          return true;
        case 'transcribe':
          transcripts++;
          return transcripts.isOdd ? '수민아?' : '제주도는?';
        case 'cancel':
          return null;
      }
      throw MissingPluginException();
    });
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      switch (call.method) {
        case 'play':
          expect(call.arguments, isA<Map>());
          expect((call.arguments as Map)['concurrentMic'], true);
          return null;
        case 'waitFinished':
          return finished.future;
        case 'stop':
          stopCalls++;
          await delayedStop.future;
          if (!finished.isCompleted) finished.complete(false);
          return null;
      }
      throw MissingPluginException();
    });
    try {
      await tester.pumpWidget(
        PatientMicDemo(
          textTrial: (client, endpoint, token, transcript, label) async {
            textCalls++;
            expect(endpoint.path, '/internal/synthetic/text');
            expect(label, 'DIRECTED');
            return SyntheticCloudReply(
              transcript,
              '응, 왜?',
              textCalls.isOdd ? Uint8List.fromList([1, 2, 3]) : null,
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
      expect(fake.lastConfig?.echoCancel, true);
      expect((textCalls, fake.stops), (1, 1));

      fake.feedCandidate();
      await _until(tester, () => stopCalls == 1);
      expect(
        (transcripts, textCalls),
        (1, 1),
        reason: 'next turn waits for confirmed playback stop',
      );
      delayedStop.complete();
      await _until(tester, () => transcripts == 2);
      expect(
        textCalls,
        1,
        reason: 'TTS echo cannot be auto-sent to hosted LLM',
      );
      final confirm = find.text('끼어든 글이 내 목소리였음 확인 · 글 보내기');
      expect(confirm, findsOneWidget);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await _until(tester, () => textCalls == 2);
      expect(
        stopCalls,
        1,
        reason: 'reply stop must finish before second STT/cloud turn',
      );
      expect((transcripts, fake.stops), (2, 2));
      expect(find.text('기기 내 전사: 제주도는?'), findsOneWidget);

      await _until(tester, () => fake.starts == 3);
      expect(
        fake.lastConfig?.echoCancel,
        false,
        reason: 'no-MP3 safe path resumes the ordinary idle mic',
      );
      fake.feedCandidate();
      await _until(tester, () => textCalls == 3 && fake.starts == 4);
      fake.feedCandidate();
      await _until(
        tester,
        () => transcripts == 4 && confirm.evaluate().isNotEmpty,
      );
      expect(
        textCalls,
        3,
        reason: 'interrupted echo candidate is still local only',
      );
      await tester.ensureVisible(find.byType(FilterChip));
      await tester.tap(find.byType(FilterChip));
      await _until(tester, () => fake.stops == 4 && fake.starts == 5);
      expect(fake.lastConfig?.echoCancel, false, reason: 'turning off barge-in replaces the shared mic with normal idle capture');
      expect(confirm, findsNothing, reason: 'turning off the experiment discards the unconfirmed interrupted text');
      fake.feedCandidate();
      await _until(tester, () => textCalls == 4 && fake.starts == 6);
      expect(textCalls, 4, reason: 'normal on-device candidate recognition resumes after chip withdrawal');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(fake.stops, 6, reason: 'withdrawal must stop the normal idle microphone');
      expect(
        textCalls,
        4,
        reason: 'self-voice withdrawal sends no extra text',
      );
      expect(confirm, findsNothing);
      expect(find.text('기기 내 전사: 제주도는?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    } finally {
      if (!delayedStop.isCompleted) delayedStop.complete();
      if (!finished.isCompleted) finished.complete(false);
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
