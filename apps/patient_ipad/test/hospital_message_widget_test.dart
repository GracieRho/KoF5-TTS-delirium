import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/on_device_speech.dart';
import 'package:kof5_patient/synthetic_hospital_message.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets(
    'approved original is shown; withdrawal during playback cannot claim delivery',
    (tester) async {
      final original = RecordPlatform.instance;
      final fake = FakeRecorderPlatform()..permission.complete(true);
      RecordPlatform.instance = fake;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const audioChannel = MethodChannel('kof5/trial_audio');
      const messageId = '00000000-0000-4000-8000-000000000903';
      const approved = '오늘 오후 4시에 CT 촬영 예정입니다.';
      final session = AnonymousDeviceSession(
        '00000000-0000-4000-8000-000000000901',
        'header.payload.signature',
        DateTime.now().add(const Duration(minutes: 30)),
      );
      final waitFinished = Completer<bool>();
      var confirms = 0;
      var audioCalls = 0;
      var stopCalls = 0;
      messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, (call) async {
        switch (call.method) {
          case 'available':
          case 'authorize':
            return true;
          case 'cancel':
            return null;
        }
        throw MissingPluginException();
      });
      messenger.setMockMethodCallHandler(audioChannel, (call) async {
        switch (call.method) {
          case 'play':
            return null;
          case 'waitFinished':
            return waitFinished.future;
          case 'stop':
            stopCalls++;
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
            dueHospitalMessageIds: (client, url, key, current) async => [
              messageId,
            ],
            confirmHospitalMessage: (client, url, key, current, id) async {
              confirms++;
              expect(id, messageId);
              return DueHospitalMessage(messageId, approved, DateTime.now());
            },
            hospitalMessageAudio: (client, url, token, current, message) async {
              audioCalls++;
              expect(message.approvedText, approved);
              expect(
                url.path,
                '/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
              );
              return Uint8List.fromList([1, 2, 3]);
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
          () => find.textContaining(session.userId).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('병원 연결 확인'));
        await tester.tap(find.text('병원 연결 확인'));
        await _until(
          tester,
          () => find.textContaining('합성 기기 연결을 확인했습니다').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('전달 대기 승인 메시지 확인'));
        await tester.tap(find.text('전달 대기 승인 메시지 확인'));
        await _until(tester, () => confirms == 1 && fake.stops == 1);
        expect(find.textContaining('직원 승인 원문: $approved'), findsOneWidget);
        expect(find.textContaining('DB 전달 상태는 변경하지 않았습니다.'), findsNothing);

        await tester.ensureVisible(find.text('승인 원문 음성 재생 시험'));
      await tester.tap(find.text('승인 원문 음성 재생 시험'));
      await _until(tester, () => audioCalls == 1 && confirms == 2);
      await _until(tester,
          () => find.textContaining('재생하고 있습니다.').evaluate().isNotEmpty);
        expect(find.textContaining('재생하고 있습니다.'), findsOneWidget);
        expect(find.textContaining('DB 전달 상태는 변경하지 않았습니다.'), findsNothing);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await _until(tester, () => stopCalls > 0);
        waitFinished.complete(true); // Late native completion after withdrawal.
        await tester.pump();
        expect(find.textContaining('직원 승인 원문: $approved'), findsNothing);
        expect(find.textContaining('DB 전달 상태는 변경하지 않았습니다.'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, null);
        messenger.setMockMethodCallHandler(audioChannel, null);
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
