import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/services/approved_bedside_context.dart';

void main() {
  const key = 'sb_publishable_synthetic_local_test_key_12345';
  const encounterId = '00000000-0000-4000-8000-000000000902';
  final session = AnonymousDeviceSession(
    '00000000-0000-4000-8000-000000000901',
    'header.payload.signature',
    DateTime.now().add(const Duration(minutes: 30)),
  );
  const pair = DevicePairContext(syntheticPatientId, encounterId);

  test(
    'approved facts populate exact context and labeled schedule content',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/rest/v1/hospital_context_current');
        expect(
          request.uri.queryParameters['patient_id'],
          'eq.$syntheticPatientId',
        );
        expect(
          request.uri.queryParameters['select'],
          'patient_id,encounter_id,category,content',
        );
        expect(request.headers.value('apikey'), key);
        expect(request.headers.value('Accept-Profile'), 'api');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${session.accessToken}',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            _fact('hospital', '승인 병원', null),
            _fact('ward', '승인 병동', encounterId),
            _fact('room', '승인 병실', encounterId),
            _fact('test_schedule', 'CT 촬영은 오늘 오후입니다.', encounterId),
            _fact('visit_schedule', '보호자 면회가 예정되어 있습니다.', encounterId),
          ]),
        );
        await request.response.close();
      });
      final client = HttpClient();
      try {
        final data = await fetchApprovedBedsideData(
          client,
          Uri.parse('http://127.0.0.1:${server.port}'),
          key,
          session,
          pair,
          allowEphemeralLoopbackForTest: true,
        );
        expect(data?.context.hospital, '승인 병원');
        expect(data?.context.ward, '승인 병동');
        expect(data?.context.room, '승인 병실');
        expect(
          data?.schedule.map((item) => (item.timeLabel, item.title)).toList(),
          [('검사 일정', 'CT 촬영은 오늘 오후입니다.'), ('면회 일정', '보호자 면회가 예정되어 있습니다.')],
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test('missing or ambiguous orientation returns no bedside data', () async {
    for (final rows in [
      [_fact('hospital', '승인 병원', null), _fact('room', '승인 병실', encounterId)],
      [
        _fact('hospital', '승인 병원', null),
        _fact('ward', '승인 병동', encounterId),
        _fact('room', '승인 병실 A', encounterId),
        _fact('room', '승인 병실 B', encounterId),
      ],
    ]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(rows));
        await request.response.close();
      });
      final client = HttpClient();
      try {
        expect(
          await fetchApprovedBedsideData(
            client,
            Uri.parse('http://127.0.0.1:${server.port}'),
            key,
            session,
            pair,
            allowEphemeralLoopbackForTest: true,
          ),
          isNull,
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    }
  });
}

Map<String, Object?> _fact(
  String category,
  String content,
  String? encounter,
) => {
  'patient_id': syntheticPatientId,
  'encounter_id': encounter,
  'category': category,
  'content': content,
};
