import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';

void main() {
  test(
    'anonymous REST signup holds only a bounded JWT; pair is DB-confirmed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      const key = 'sb_publishable_synthetic_local_test_key_12345';
      const userId = '00000000-0000-4000-8000-000000000901';
      const encounterId = '00000000-0000-4000-8000-000000000902';
      final expiry =
          DateTime.now()
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch ~/
          1000;
      final claims = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': userId,
                'role': 'authenticated',
                'is_anonymous': true,
                'exp': expiry,
              }),
            ),
          )
          .replaceAll('=', '');
      final jwt =
          '${base64Url.encode(utf8.encode('{}')).replaceAll('=', '')}.$claims.signature';
      var calls = 0;
      server.listen((request) async {
        calls++;
        expect(request.headers.value('apikey'), key);
        request.response.headers.contentType = ContentType.json;
        if (calls == 1) {
          expect(request.method, 'POST');
          expect(request.uri.path, '/auth/v1/signup');
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          expect(body['data'], isEmpty);
          expect(body['gotrue_meta_security'], {'captcha_token': null});
          request.response.write(
            jsonEncode({
              'access_token': jwt,
              'token_type': 'bearer',
              'expires_in': 1800,
              'expires_at': expiry,
              'refresh_token': 'must-not-be-kept',
              'user': {'id': userId, 'is_anonymous': true},
            }),
          );
        } else {
          expect(request.method, 'GET');
          expect(request.uri.path, '/rest/v1/patient_device_context');
          expect(request.headers.value('Accept-Profile'), 'api');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer $jwt',
          );
          request.response.write(
            jsonEncode([
              {'patient_id': syntheticPatientId, 'encounter_id': encounterId},
            ]),
          );
        }
        await request.response.close();
      });
      final client = HttpClient();
      try {
        final project = Uri.parse('http://127.0.0.1:${server.port}');
        final session = await signInAnonymousDevice(
          client,
          project,
          key,
          allowEphemeralLoopbackForTest: true,
        );
        expect(session.userId, userId);
        expect(session.accessToken, jwt);
        expect(session.usable(DateTime.now()), isTrue);
        expect(session.toString(), isNot(contains('must-not-be-kept')));
        final pair = await confirmSyntheticDevicePair(
          client,
          project,
          key,
          session,
          allowEphemeralLoopbackForTest: true,
        );
        expect(
          (pair.patientId, pair.encounterId),
          (syntheticPatientId, encounterId),
        );
        expect(calls, 2);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test('shared project and secret key fail before network', () {
    const publishable = 'sb_publishable_synthetic_local_test_key_12345';
    expect(
      () => checkDedicatedSupabase(
        Uri.parse('https://abcdefghijklmnopqrst.supabase.co'),
        publishable,
      ),
      throwsFormatException,
    );
    expect(
      () => checkDedicatedSupabase(
        Uri.parse('http://127.0.0.1:54321'),
        publishable,
      ),
      throwsFormatException,
    );
    expect(
      () => checkDedicatedSupabase(
        Uri.parse('https://dqjplezbvtjbsunabxbg.supabase.co'),
        publishable,
      ),
      throwsFormatException,
    );
    expect(
      () => checkDedicatedSupabase(
        Uri.parse('https://abcdefghijklmnopqrst.supabase.co'),
        'sb_secret_never_on_ipad_123456789',
      ),
      throwsFormatException,
    );
  });
}
