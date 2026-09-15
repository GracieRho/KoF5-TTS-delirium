import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/synthetic_auxiliary_alert.dart';
import 'package:kof5_patient/synthetic_risk_candidate.dart';

void main() {
  const key = 'sb_publishable_synthetic_local_test_key_12345';
  const alertId = '00000000-0000-4000-8000-000000000904';
  const idempotency = '00000000-0000-4000-8000-000000000905';
  final session = AnonymousDeviceSession(
    '00000000-0000-4000-8000-000000000901',
    'header.payload.signature',
    DateTime.now().add(const Duration(minutes: 30)),
  );

  test('device RPC sends category/idempotency only, never transcript', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    server.listen((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.uri.path, '/rest/v1/rpc/synthetic_alert_create');
      expect(request.headers.value('apikey'), key);
      expect(request.headers.value('Content-Profile'), 'api');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer ${session.accessToken}',
      );
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body, {
        'p_patient_id': syntheticPatientId,
        'p_risk_category': 'breathing',
        'p_idempotency_key': idempotency,
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {'authorized': true, 'alert_id': alertId, 'state': 'created'},
        ]),
      );
      await request.response.close();
    });
    final client = HttpClient();
    try {
      final candidate = SyntheticRiskCandidate.fromDirectedOwnVoice(
        '수민아, 숨을 못 쉬겠어',
      )!;
      final result = await createSyntheticAuxiliaryAlert(
        client,
        Uri.parse('http://127.0.0.1:${server.port}'),
        key,
        session,
        candidate,
        idempotency,
        allowEphemeralLoopbackForTest: true,
      );
      expect(result.alertId, alertId);
      expect(calls, 1);
      expect(
        newSyntheticAlertIdempotencyKey(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test('denied response and unrelated Supabase URL fail closed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    server.listen((request) async {
      calls++;
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {'authorized': false, 'alert_id': null, 'state': null},
        ]),
      );
      await request.response.close();
    });
    final client = HttpClient();
    final candidate = SyntheticRiskCandidate.fromDirectedOwnVoice(
      '수민아, 가슴이 아파',
    )!;
    try {
      await expectLater(
        createSyntheticAuxiliaryAlert(
          client,
          Uri.parse('http://127.0.0.1:${server.port}'),
          key,
          session,
          candidate,
          idempotency,
          allowEphemeralLoopbackForTest: true,
        ),
        throwsFormatException,
      );
      expect(calls, 1);
      await expectLater(
        createSyntheticAuxiliaryAlert(
          client,
          Uri.parse('https://abcdefghijklmnopqrst.supabase.co'),
          key,
          session,
          candidate,
          idempotency,
        ),
        throwsFormatException,
      );
      expect(calls, 1);
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}
