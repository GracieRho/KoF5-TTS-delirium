import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/on_device_speech.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets('unpaired device cannot send; stopped JWT cannot fall back', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform()..permission.complete(true);
    RecordPlatform.instance = fake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const userId = '00000000-0000-4000-8000-000000000901';
    const jwt = 'header.payload.signature';
    var legacyCalls = 0;
    var pairedCalls = 0;
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
    try {
      await tester.pumpWidget(
        PatientMicDemo(
          deviceSignIn: (client, url, key) async {
            expect(url.toString(), 'http://127.0.0.1:54341');
            expect(key, startsWith('sb_publishable_'));
            return AnonymousDeviceSession(
              userId,
              jwt,
              DateTime.now().add(const Duration(minutes: 30)),
            );
          },
          devicePair: (client, url, key, session) async {
            expect(session.userId, userId);
            return const DevicePairContext(
              syntheticPatientId,
              '00000000-0000-4000-8000-000000000902',
            );
          },
          textTrial: (client, url, token, transcript, label) async {
            legacyCalls++;
            return const SyntheticCloudReply('수민아?', null, null);
          },
          pairedTextTrial:
              (client, url, token, transcript, label, bearer, patientId) async {
                pairedCalls++;
                expect(
                  url.path,
                  '/internal/synthetic/paired/$syntheticPatientId/text',
                );
                expect((bearer, patientId), (jwt, syntheticPatientId));
                return const SyntheticCloudReply('수민아?', '응, 왜?', null);
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
      final login = find.text('익명 기기 ID 만들기');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await _until(
        tester,
        () => find.textContaining(userId).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect((legacyCalls, pairedCalls), (0, 0));
      expect(
        find.textContaining('연결과 유효한 JWT가 없어 글을 보내지 않았습니다'),
        findsOneWidget,
      );

      final pair = find.text('병원 연결 확인');
      await tester.ensureVisible(pair);
      await tester.tap(pair);
      await _until(
        tester,
        () => find.textContaining('합성 기기 연결을 확인했습니다').evaluate().isNotEmpty,
      );
      fake.feedCandidate();
      await _until(tester, () => pairedCalls == 1 && fake.starts == 2);
      expect(legacyCalls, 0);

      await tester.ensureVisible(find.text('시험 중단'));
      await tester.tap(find.text('시험 중단'));
      await _until(tester, () => fake.stops == 2);
      await _until(tester, () => find.text('마이크 시험 시작').evaluate().isNotEmpty);
      expect(
        find.textContaining(userId),
        findsNothing,
        reason:
            'manual stop clears in-memory device JWT and visible pairing ID',
      );
      await tester.ensureVisible(find.text('마이크 시험 시작'));
      await tester.tap(find.text('마이크 시험 시작'));
      await _until(tester, () => fake.starts == 3);
      fake.feedCandidate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(
        (legacyCalls, pairedCalls),
        (0, 1),
        reason: 'expired/cleared paired mode never falls back to legacy text',
      );
      await tester.ensureVisible(find.text('시험 중단'));
      await tester.tap(find.text('시험 중단'));
      await _until(tester, () => fake.stops == 3);
      await tester.pumpWidget(const SizedBox());
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
