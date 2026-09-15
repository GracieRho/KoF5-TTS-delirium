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
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordPlatform original;
  late FakeRecorderPlatform fake;
  var available = true;
  var transcripts = 0;
  var recognizedText = '수민아?';
  Future<String?>? pendingTranscript;
  Future<void>? pendingCancel;
  var cancelFails = false;
  var cancelCalls = 0;
  final textCalls = <(String, String, String)>[];

  setUp(() {
    original = RecordPlatform.instance;
    fake = FakeRecorderPlatform();
    fake.permission.complete(true);
    RecordPlatform.instance = fake;
    available = true;
    transcripts = 0;
    recognizedText = '수민아?';
    pendingTranscript = null;
    pendingCancel = null;
    cancelFails = false;
    cancelCalls = 0;
    textCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
          switch (call.method) {
            case 'available':
              return available;
            case 'authorize':
              return true;
            case 'transcribe':
              transcripts++;
              expect(call.arguments, isA<Uint8List>());
              return pendingTranscript ?? recognizedText;
            case 'cancel':
              cancelCalls++;
              if (pendingCancel != null) {
                await pendingCancel;
                return null;
              }
              if (cancelFails) throw PlatformException(code: 'cancel_failed');
              return null;
          }
          throw MissingPluginException();
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OnDeviceSpeech.channel, null);
    RecordPlatform.instance = original;
  });

  Future<void> startOwnVoice(WidgetTester tester) async {
    await tester.pumpWidget(
      PatientMicDemo(
        textTrial: (client, endpoint, token, transcript, label) async {
          textCalls.add((endpoint.path, transcript, label));
          return SyntheticCloudReply(transcript, '응, 왜?', null);
        },
      ),
    );
    await tester.tap(find.text('마이크 시험 시작'));
    for (var i = 0; i < 20 && fake.starts == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    for (
      var i = 0;
      i < 20 && find.text('기기에서 듣고 있습니다').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      find.text('기기에서 듣고 있습니다'),
      findsOneWidget,
      reason:
          'fake.starts=${fake.starts}, fake.stops=${fake.stops}; '
          '${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (available) {
      expect(find.textContaining('한국어 기기 내 전사 준비됨'), findsOneWidget);
    }
  }

  Future<void> finishWidget(WidgetTester tester) async {
    if (find.text('시험 중단').evaluate().isNotEmpty) {
      final priorStops = fake.stops;
      await tester.ensureVisible(find.text('시험 중단'));
      await tester.tap(find.text('시험 중단'));
      for (var i = 0; i < 20 && fake.stops == priorStops; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(fake.stops, priorStops + 1);
      for (
        var i = 0;
        i < 20 && find.text('마이크 시험을 중단했습니다.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('마이크 시험을 중단했습니다.'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }

  testWidgets(
    'local speech respects support and withdrawal, including late results',
    (tester) async {
      await startOwnVoice(tester);
      Future<void> restartMic() async {
        for (var i = 0; i < 40 && find.text('마이크 시험 시작').evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(find.text('마이크 시험 시작'), findsOneWidget,
          reason: 'withdrawal should stop capture before restart; starts=${fake.starts} stops=${fake.stops} texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}');
        await tester.ensureVisible(find.text('마이크 시험 시작'));
        await tester.tap(find.text('마이크 시험 시작'));
        await tester.pump();
        for (var i = 0; i < 40 && find.text('기기에서 듣고 있습니다').evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(find.text('기기에서 듣고 있습니다'), findsOneWidget, reason: 'new mic must be active before feeding a candidate');
      }
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(transcripts, 1);
      expect(find.text('기기 내 전사: 수민아?'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(find.text('기기 내 전사: 수민아?'), findsNothing);

      available = false;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await restartMic();
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(
        transcripts,
        1,
        reason: 'unsupported Korean recognition cannot receive PCM',
      );
      expect(find.textContaining('지원하지 않아 후보를 전사하지 않습니다'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, false);
      for (var i = 0; i < 40 && fake.stops < 2; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(fake.stops, 2, reason: 'second consent withdrawal stops normal capture');

      final late = Completer<String?>();
      pendingTranscript = late.future;
      available = true;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await restartMic();
      fake.feedCandidate();
      for (var i = 0; i < 20 && transcripts < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(transcripts, 2);
      final delayedCancel = Completer<void>();
      pendingCancel = delayedCancel.future;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(find.textContaining('중단 확인 중'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(transcripts, 2, reason: 'pending cancel blocks a new recognition');
      delayedCancel.complete();
      pendingCancel = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.textContaining('한국어 기기 내 전사 준비됨'), findsOneWidget);
      late.complete('늦게 온 환자 발화');
      await tester.pump();
      expect(find.textContaining('늦게 온 환자 발화'), findsNothing);

      pendingTranscript = null;
      await restartMic();
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(transcripts, 3);
      cancelFails = true;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.textContaining('중단을 확인하지 못했습니다'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      fake.feedCandidate();
      await tester.pump();
      expect(
        transcripts,
        3,
        reason: 'failed retry cannot unlock native recognition',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '자가 음성 후보 한 건 보내기'),
            )
            .onPressed,
        isNull,
      );
      cancelFails = false;
      await tester.tap(find.text('전사 중단 다시 확인'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.textContaining('한국어 기기 내 전사 준비됨'), findsOneWidget);
      expect(cancelCalls, greaterThanOrEqualTo(3));
      await restartMic();
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(transcripts, 4);
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/internal/synthetic/audio',
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 32);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      final priorStops = fake.stops;
      fake.feedCandidate();
      for (var i = 0; i < 30 && textCalls.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(textCalls, [('/internal/synthetic/text', '수민아?', 'DIRECTED')]);
      expect(
        fake.stops,
        priorStops + 1,
        reason: 'text-only request follows confirmed mic stop',
      );
      expect(find.text('응, 왜?'), findsOneWidget);
      await finishWidget(tester);
    },
  );

  test('rejects malformed PCM and oversized native transcript', () async {
    const speech = OnDeviceSpeech();
    await expectLater(speech.transcribe(Uint8List(3)), throwsFormatException);
    expect(transcripts, 0);
    recognizedText = '가' * 501;
    await expectLater(
      speech.transcribe(Uint8List(3200)),
      throwsFormatException,
    );
    expect(transcripts, 1);
  });
}
