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
  const messageId = '00000000-0000-4000-8000-000000000903';
  const approved = '오늘 오후 4시에 CT 촬영 예정입니다.';
  for (final scenario in [
    'zero',
    'due',
    'withdrawn',
    'stop-finished-race',
    'uncertain',
  ]) {
    testWidgets('scheduled hospital delivery: $scenario', (tester) async {
      final original = RecordPlatform.instance;
      final fake = FakeRecorderPlatform()..permission.complete(true);
      RecordPlatform.instance = fake;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const audio = MethodChannel('kof5/trial_audio');
      final finished = Completer<bool>();
      final delayedStop = Completer<void>();
      final session = AnonymousDeviceSession(
        '00000000-0000-4000-8000-000000000901',
        'header.payload.signature',
        DateTime.now().add(const Duration(minutes: 30)),
      );
      var dueCalls = 0;
      var confirms = 0;
      var audioCalls = 0;
      var playCalls = 0;
      var finishedCalls = 0;
      var stopCalls = 0;
      var ackCalls = 0;
      String? attempt;
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
      messenger.setMockMethodCallHandler(audio, (call) async {
        switch (call.method) {
          case 'play':
            playCalls++;
            return null;
          case 'waitFinished':
            finishedCalls++;
            return scenario == 'uncertain' ? true : finished.future;
          case 'stop':
            stopCalls++;
            if (scenario == 'stop-finished-race') await delayedStop.future;
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
            dueHospitalMessageIds: (client, url, key, current) async {
              dueCalls++;
              expect(current, same(session));
              return scenario == 'zero' ? <String>[] : [messageId];
            },
            confirmHospitalMessage: (client, url, key, current, id) async {
              confirms++;
              expect(id, messageId);
              if (confirms == 2) {
                expect(
                  fake.stops,
                  1,
                  reason: 'approval is rechecked after confirmed mic stop',
                );
              }
              return DueHospitalMessage(messageId, approved, DateTime.now());
            },
            hospitalMessageAudio: (client, url, token, current, message) async {
              audioCalls++;
              expect(confirms, 2);
              expect(message.approvedText, approved);
              return Uint8List.fromList([1, 2, 3]);
            },
            hospitalPlaybackComplete:
                (client, url, key, current, id, attemptId) async {
                  ackCalls++;
                  expect(id, messageId);
                  expect(current, same(session));
                  expect(finishedCalls, 1);
                  expect(playCalls, 1);
                  expect(fake.stops, 1);
                  expect(
                    attemptId,
                    matches(
                      RegExp(
                        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                      ),
                    ),
                  );
                  attempt ??= attemptId;
                  expect(attemptId, attempt);
                  if (scenario == 'uncertain' && ackCalls == 1) {
                    throw StateError('response lost after possible commit');
                  }
                  return true;
                },
          ),
        );
        await _pairTester(tester, fake, session);
        await tester.ensureVisible(find.text('예약 메시지 자동 확인 켜기 · 합성 시험'));
        await tester.tap(find.text('예약 메시지 자동 확인 켜기 · 합성 시험'));
        await _until(tester, () => dueCalls == 1);

        if (scenario == 'zero') {
          await _until(
            tester,
            () => find.textContaining('기기 듣기를 유지합니다.').evaluate().isNotEmpty,
          );
          expect(
            (fake.starts, fake.stops, confirms, audioCalls, ackCalls),
            (1, 0, 0, 0, 0),
          );
          await tester.pump(const Duration(seconds: 30));
          await _until(tester, () => dueCalls == 2);
          expect((fake.starts, fake.stops), (1, 0));
        } else {
          await _until(tester, () => finishedCalls == 1);
          expect((confirms, audioCalls, playCalls, fake.stops), (2, 1, 1, 1));
          if (scenario != 'uncertain') {
            expect(
              ackCalls,
              0,
              reason: 'native playback completion is the only ACK trigger',
            );
          }
          if (scenario == 'withdrawn') {
            await tester.ensureVisible(find.byType(CheckboxListTile));
            await tester.tap(find.byType(CheckboxListTile));
            finished.complete(true);
            await _until(tester, () => stopCalls > 0);
            expect(ackCalls, 0);
            expect(find.textContaining('DB 전달 확인을 받았습니다.'), findsNothing);
          } else if (scenario == 'stop-finished-race') {
            await tester.ensureVisible(find.text('음성 응답 중단'));
            await tester.tap(find.text('음성 응답 중단'));
            await _until(tester, () => stopCalls == 1);
            finished.complete(
              true,
            ); // Native completion races an unconfirmed stop.
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
            expect(ackCalls, 0);
            expect(
              fake.starts,
              1,
              reason: 'stop intent cannot auto-resume the scheduled mic',
            );
            expect(find.textContaining('DB 전달 확인을 받았습니다.'), findsNothing);
            delayedStop.complete();
            await _until(
              tester,
              () => find
                  .textContaining('병원 음성 재생과 예약 자동 확인을 중단했습니다.')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(ackCalls, 0);
            expect(fake.starts, 1);
            await tester.pump(const Duration(seconds: 30));
            await tester.pump();
            expect(
              (dueCalls, playCalls, ackCalls),
              (1, 1, 0),
              reason:
                  'explicit stop cannot automatically replay pending due ID',
            );
          } else {
            if (scenario == 'due') finished.complete(true);
            await _until(tester, () => ackCalls == 1);
            if (scenario == 'uncertain') {
              await _until(
                tester,
                () =>
                    find.textContaining('DB 응답이 불확실합니다.').evaluate().isNotEmpty,
              );
              expect(find.textContaining('DB 전달 확인을 받았습니다.'), findsNothing);
              await tester.pump(const Duration(seconds: 30));
              await _until(tester, () => ackCalls == 2);
              expect(
                playCalls,
                1,
                reason: 'same attempt retries DB ACK without replay',
              );
            }
            await _until(
              tester,
              () =>
                  find.textContaining('DB 전달 확인을 받았습니다.').evaluate().isNotEmpty,
            );
            expect(ackCalls, scenario == 'due' ? 1 : 2);
            await _until(tester, () => fake.starts == 2);
            await tester.pump(const Duration(seconds: 30));
            await tester.pump();
            expect(
              playCalls,
              1,
              reason: 'same app session never repeats completed playback',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
        await _until(tester, () => fake.audio.isClosed);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      } finally {
        if (!finished.isCompleted) finished.complete(false);
        if (!delayedStop.isCompleted) delayedStop.complete();
        messenger.setMockMethodCallHandler(audio, null);
        messenger.setMockMethodCallHandler(OnDeviceSpeech.channel, null);
        RecordPlatform.instance = original;
      }
    });
  }
}

Future<void> _pairTester(
  WidgetTester tester,
  FakeRecorderPlatform fake,
  AnonymousDeviceSession session,
) async {
  await tester.tap(find.text('마이크 시험 시작'));
  for (var i = 0; i < 60 && fake.starts == 0; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    fake.starts,
    greaterThanOrEqualTo(1),
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((text) => text?.contains('마이크') == true)
        .toList()
        .toString(),
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
