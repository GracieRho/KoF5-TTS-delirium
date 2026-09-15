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
  testWidgets(
    'only live accepted candidate shows timing after native play confirms',
    (tester) async {
      final original = RecordPlatform.instance;
      final fake = FakeRecorderPlatform()..permission.complete(true);
      RecordPlatform.instance = fake;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const audio = MethodChannel('kof5/trial_audio');
      final pendingPlay = Completer<void>();
      final latePlay = Completer<void>();
      var currentPlay = pendingPlay;
      var recognized = 'TV 뉴스입니다';
      var textCalls = 0;
      messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
        switch (call.method) {
          case 'available':
          case 'authorize':
            return true;
          case 'transcribe':
            return recognized;
          case 'cancel':
            return null;
        }
        throw MissingPluginException();
      });
      messenger.setMockMethodCallHandler(audio, (call) async {
        switch (call.method) {
          case 'play':
            await currentPlay.future;
            return null;
          case 'stop':
            return null;
          case 'waitFinished':
            return false;
        }
        throw MissingPluginException();
      });
      try {
        await tester.pumpWidget(
          PatientMicDemo(
            textTrial: (client, endpoint, token, transcript, label) async {
              textCalls++;
              return SyntheticCloudReply(
                transcript,
                '응, 왜?',
                Uint8List.fromList([1, 2, 3]),
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

        fake.feedCandidate();
        await _until(
          tester,
          () => find.textContaining('기기 내 전사 완료').evaluate().isNotEmpty,
        );
        expect(textCalls, 0);
        expect(find.textContaining('TV 뉴스입니다'), findsNothing);
        expect(find.textContaining('기기 발화 후보 확정'), findsNothing);

        recognized = '수민아?';
        fake.feedCandidate();
        await _until(tester, () => textCalls == 1 && fake.stops == 1);
        expect(
          find.textContaining('기기 발화 후보 확정'),
          findsNothing,
          reason: 'network response does not confirm native playback',
        );
        pendingPlay.complete();
        await _until(
          tester,
          () => find
              .textContaining('기기 발화 후보 확정 → 재생 시작 명령 확인:')
              .evaluate()
              .isNotEmpty,
        );

        await tester.ensureVisible(find.text('음성 응답 중단'));
        await tester.tap(find.text('음성 응답 중단'));
        await _until(
          tester,
          () => find.textContaining('기기 발화 후보 확정').evaluate().isEmpty,
        );
        await _until(
          tester,
          () => find.text('음성 응답 재생을 중단했습니다.').evaluate().isNotEmpty,
        );

        currentPlay = latePlay;
        await tester.ensureVisible(find.text('마이크 시험 시작'));
        await tester.tap(find.text('마이크 시험 시작'));
        await _until(tester, () => fake.starts == 2);
        fake.feedCandidate();
        await _until(tester, () => textCalls == 2 && fake.stops == 2);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        latePlay.complete();
        await _until(
          tester,
          () => find.text('내 목소리로만 시험합니다').evaluate().isNotEmpty,
        );
        expect(
          find.textContaining('기기 발화 후보 확정'),
          findsNothing,
          reason: 'late native acknowledgment after withdrawal is stale',
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        if (!pendingPlay.isCompleted) pendingPlay.complete();
        if (!latePlay.isCompleted) latePlay.complete();
        messenger.setMockMethodCallHandler(audio, null);
        messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, null);
        RecordPlatform.instance = original;
      }
    },
  );
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
