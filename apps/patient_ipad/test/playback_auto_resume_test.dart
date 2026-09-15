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
  testWidgets('natural reply finish resumes only the live opt-in mic', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform();
    fake.permission.complete(true);
    RecordPlatform.instance = fake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final finishes = <Completer<bool>>[];
    var playCalls = 0;
    var textCalls = 0;
    const audioChannel = MethodChannel('kof5/trial_audio');
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
          playCalls++;
          return null;
        case 'waitFinished':
          final pending = Completer<bool>();
          finishes.add(pending);
          return pending.future;
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
            expect(endpoint.path, '/internal/synthetic/text');
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
      await _until(tester, () => finishes.length == 1);
      expect((textCalls, playCalls, fake.stops), (1, 1, 1));
      expect(fake.starts, 1, reason: 'mic stays off while reply is playing');
      finishes.first.complete(true);
      await _until(tester, () => fake.starts == 2);
      expect(find.text('기기에서 듣고 있습니다'), findsOneWidget);

      fake.feedCandidate();
      await _until(tester, () => finishes.length == 2);
      expect((textCalls, playCalls, fake.stops), (2, 2, 2));
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      finishes.last.complete(
        true,
      ); // Late native finish after consent withdrawal.
      await _until(
        tester,
        () => find.text('내 목소리로만 시험합니다').evaluate().isNotEmpty,
      );
      expect(
        fake.starts,
        2,
        reason: 'withdrawal cannot rearm always-listening',
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      for (final finish in finishes) {
        if (!finish.isCompleted) finish.complete(false);
      }
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
