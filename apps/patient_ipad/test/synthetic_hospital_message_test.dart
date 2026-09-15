import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/synthetic_hospital_message.dart';

void main() {
  const key = 'sb_publishable_synthetic_local_test_key_12345';
  const messageId = '00000000-0000-4000-8000-000000000903';
  const approved = '오늘 오후 4시에 CT 촬영 예정입니다.';
  final session = AnonymousDeviceSession(
    '00000000-0000-4000-8000-000000000901',
    'header.payload.signature',
    DateTime.now().add(const Duration(minutes: 30)),
  );

  test(
    'device discovers IDs, rechecks exact approved text, then requests MP3 without ACK',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final due = DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String();
      server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.method, 'POST');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${session.accessToken}',
        );
        request.response.headers.contentType = ContentType.json;
        final body = await utf8.decoder.bind(request).join();
        if (paths.length < 3) {
          expect(request.headers.value('apikey'), key);
          expect(request.headers.value('Content-Profile'), 'api');
          expect(jsonDecode(body)['_patient_id'], syntheticPatientId);
        }
        switch (request.uri.path) {
          case '/rest/v1/rpc/synthetic_due_hospital_message_ids':
            request.response.write(
              jsonEncode([
                {'message_id': messageId, 'due_at': due},
              ]),
            );
          case '/rest/v1/rpc/synthetic_due_hospital_message':
            expect(jsonDecode(body)['_message_id'], messageId);
            request.response.write(
              jsonEncode([
                {
                  'authorized': true,
                  'message_id': messageId,
                  'approved_text': approved,
                  'due_at': due,
                },
              ]),
            );
          default:
            expect(
              request.uri.path,
              '/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
            );
            expect(body, isEmpty);
            expect(request.headers.value('X-Internal-Demo-Token'), 'x' * 32);
            expect(request.headers.value('X-Synthetic-Material'), 'confirmed');
            request.response.write(
              jsonEncode({
                'approved_text': approved,
                'audio_mp3_base64': base64Encode([1, 2, 3]),
              }),
            );
        }
        await request.response.close();
      });
      final client = HttpClient();
      try {
        final project = Uri.parse('http://127.0.0.1:${server.port}');
        final ids = await listSyntheticDueHospitalMessageIds(
          client,
          project,
          key,
          session,
          allowEphemeralLoopbackForTest: true,
        );
        expect(ids, [messageId]);
        final message = await confirmSyntheticDueHospitalMessage(
          client,
          project,
          key,
          session,
          ids.single,
          allowEphemeralLoopbackForTest: true,
        );
        expect(message.approvedText, approved);
        final mp3 = await synthesizeSyntheticHospitalMessage(
          client,
          Uri.parse(
            'http://127.0.0.1:${server.port}/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
          ),
          'x' * 32,
          session,
          message,
          allowedOriginForTest: 'http://127.0.0.1:${server.port}',
        );
        expect(mp3, [1, 2, 3]);
        expect(paths, [
          '/rest/v1/rpc/synthetic_due_hospital_message_ids',
          '/rest/v1/rpc/synthetic_due_hospital_message',
          '/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
        ]);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test('denied RPC and mismatched API original fail closed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    server.listen((request) async {
      calls++;
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        calls == 1
            ? jsonEncode([
                {
                  'authorized': false,
                  'message_id': null,
                  'approved_text': null,
                  'due_at': null,
                },
              ])
            : jsonEncode({
                'approved_text': '바뀐 문구',
                'audio_mp3_base64': base64Encode([1, 2, 3]),
              }),
      );
      await request.response.close();
    });
    final client = HttpClient();
    try {
      final project = Uri.parse('http://127.0.0.1:${server.port}');
      await expectLater(
        confirmSyntheticDueHospitalMessage(
          client,
          project,
          key,
          session,
          messageId,
          allowEphemeralLoopbackForTest: true,
        ),
        throwsFormatException,
      );
      final message = DueHospitalMessage(messageId, approved, DateTime.now());
      await expectLater(
        synthesizeSyntheticHospitalMessage(
          client,
          Uri.parse(
            'http://127.0.0.1:${server.port}/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
          ),
          'x' * 32,
          session,
          message,
          allowedOriginForTest: 'http://127.0.0.1:${server.port}',
        ),
        throwsFormatException,
      );
      expect(calls, 2);
      await expectLater(
        synthesizeSyntheticHospitalMessage(
          client,
          Uri.parse(
            'https://example.com/internal/synthetic/paired/$syntheticPatientId/message/$messageId/audio',
          ),
          'x' * 32,
          session,
          message,
        ),
        throwsFormatException,
      );
      expect(calls, 2);
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test(
    'playback-complete RPC sends exact device attempt and reads scalar bool',
    () async {
      const attempt = '00000000-0000-4000-8000-000000000904';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(
          request.uri.path,
          '/rest/v1/rpc/synthetic_hospital_message_playback_complete',
        );
        expect(request.headers.value('apikey'), key);
        expect(request.headers.value('Content-Profile'), 'api');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${session.accessToken}',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'p_patient_id': syntheticPatientId,
          'p_message_id': messageId,
          'p_attempt_id': attempt,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write('true');
        await request.response.close();
      });
      final client = HttpClient();
      try {
        expect(
          await completeSyntheticHospitalPlayback(
            client,
            Uri.parse('http://127.0.0.1:${server.port}'),
            key,
            session,
            messageId,
            attempt,
            allowEphemeralLoopbackForTest: true,
          ),
          true,
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
