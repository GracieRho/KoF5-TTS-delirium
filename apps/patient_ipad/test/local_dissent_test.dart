import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/on_device_speech.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets('own-voice dissent stops local capture without cloud upload', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform()..permission.complete(true);
    RecordPlatform.instance = fake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final transcript = Completer<String>();
    var uploads = 0;
    messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
      switch (call.method) {
        case 'available':
        case 'authorize':
          return true;
        case 'transcribe':
          return transcript.future;
        case 'cancel':
          return null;
      }
      throw MissingPluginException();
    });
    try {
      await tester.pumpWidget(
        PatientMicDemo(
          textTrial: (client, endpoint, token, transcript, label) async {
            uploads++;
            throw StateError('dissent must never reach the server');
          },
        ),
      );
      await tester.tap(find.text('마이크 시험 시작'));
      await _until(
        tester,
        () =>
            fake.starts == 1 && find.text('기기에서 듣고 있습니다').evaluate().isNotEmpty,
      );
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
        () => find.textContaining('전사하고 있습니다').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('자가 음성 후보 한 건 준비'),
        findsNothing,
        reason:
            'text-only trial cannot retain the 30-second manual audio candidate',
      );
      transcript.complete('그만해.');
      await _until(
        tester,
        () =>
            fake.stops == 1 &&
            find.textContaining('자동 글 시험을 중단합니다').evaluate().isNotEmpty,
      );
      expect(uploads, 0);
      await _until(
        tester,
        () => find
            .widgetWithText(FilledButton, '마이크 시험 시작')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '마이크 시험 시작'),
            )
            .onPressed,
        isNull,
        reason:
            'a dissent candidate blocks manual listening restart until new self-voice consent',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '마이크 시험 시작'),
            )
            .onPressed,
        isNull,
        reason: 'discarding old trial data alone cannot clear the dissent stop',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '마이크 시험 시작'),
            )
            .onPressed,
        isNotNull,
        reason: 'new explicit self-voice confirmation unlocks local capture',
      );
      expect(uploads, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    } finally {
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
