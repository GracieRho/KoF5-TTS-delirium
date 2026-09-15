import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/on_device_speech.dart';
import 'package:kof5_patient/synthetic_auxiliary_alert.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets(
    'ambient risk is discarded; direct self-voice alert pending withdrawal cannot claim created',
    (tester) async {
      final original = RecordPlatform.instance;
      final fake = FakeRecorderPlatform()..permission.complete(true);
      RecordPlatform.instance = fake;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var recognized = '숨을 못 쉬겠어?';
      var alertCalls = 0;
      var textCalls = 0;
      final pendingAlert = Completer<SyntheticAlertCreated>();
      const sessionId = '00000000-0000-4000-8000-000000000901';
      final session = AnonymousDeviceSession(
        sessionId,
        'header.payload.signature',
        DateTime.now().add(const Duration(minutes: 30)),
      );
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
      try {
        await tester.pumpWidget(
          PatientMicDemo(
            deviceSignIn: (client, url, key) async => session,
            devicePair: (client, url, key, current) async =>
                const DevicePairContext(
                  syntheticPatientId,
                  '00000000-0000-4000-8000-000000000902',
                ),
            textTrial: (client, url, token, transcript, label) async {
              textCalls++;
              return const SyntheticCloudReply('수민아?', null, null);
            },
            pairedTextTrial:
                (client, url, token, transcript, label, jwt, patientId) async {
                  textCalls++;
                  return const SyntheticCloudReply('수민아?', null, null);
                },
            auxiliaryAlert: (client, url, key, current, candidate, idempotency) {
              alertCalls++;
              expect(url.toString(), 'http://127.0.0.1:54341');
              expect(candidate.category, 'breathing');
              expect(
                idempotency,
                matches(
                  RegExp(
                    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                  ),
                ),
              );
              return pendingAlert.future;
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
        await tester.enterText(
          find.widgetWithText(TextField, '전용 Supabase 주소'),
          'http://127.0.0.1:54341',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Supabase publishable 키'),
          'sb_publishable_synthetic_local_test_key_12345',
        );
        await tester.enterText(find.byType(TextField).last, 'x' * 32);
        await tester.ensureVisible(find.text('익명 기기 ID 만들기'));
        await tester.tap(find.text('익명 기기 ID 만들기'));
        await _until(
          tester,
          () => find.textContaining(sessionId).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('병원 연결 확인'));
        await tester.tap(find.text('병원 연결 확인'));
        await _until(
          tester,
          () => find.textContaining('합성 기기 연결을 확인했습니다').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
        fake.feedCandidate();
        await _until(
          tester,
          () => find
              .textContaining('화자가 불명확해 서버 전송을 폐기했습니다')
              .evaluate()
              .isNotEmpty,
        );
        expect((alertCalls, textCalls), (0, 0));
        expect(find.textContaining('기존 호출 버튼을 이용해주세요'), findsWidgets);

        recognized = '수민아, 숨을 못 쉬겠어';
        fake.feedCandidate();
        await _until(tester, () => alertCalls == 1 && fake.stops == 1);
        expect(textCalls, 0);
        expect(find.textContaining('기존 호출 버튼을 이용해주세요'), findsWidgets);
        expect(find.textContaining('보조 alert DB 기록 생성만 확인했습니다'), findsNothing);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        pendingAlert.complete(
          const SyntheticAlertCreated('00000000-0000-4000-8000-000000000904'),
        );
        await tester.pump();
        expect(find.textContaining('보조 alert DB 기록 생성만 확인했습니다'), findsNothing);
        expect(textCalls, 0);
        await tester.pumpWidget(const SizedBox());
        await _until(tester, () => fake.audio.isClosed);
      } finally {
        messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, null);
        RecordPlatform.instance = original;
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
