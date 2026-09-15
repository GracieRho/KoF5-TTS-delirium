import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'device_anonymous_auth.dart';
import 'synthetic_risk_candidate.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class SyntheticAlertCreated {
  const SyntheticAlertCreated(this.alertId);
  final String alertId;
}

String newSyntheticAlertIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<SyntheticAlertCreated> createSyntheticAuxiliaryAlert(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session,
  SyntheticRiskCandidate candidate,
  String idempotencyKey, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (!session.usable(DateTime.now()) ||
      !_uuid.hasMatch(idempotencyKey) ||
      !{
        'breathing',
        'chest_pain',
        'fall',
        'pain',
        'dizziness',
        'distress',
      }.contains(candidate.category) ||
      SyntheticRiskCandidate.fromDirectedOwnVoice(
            candidate.transcript,
          )?.category !=
          candidate.category) {
    throw const FormatException('확인된 합성 위험 후보와 기기 권한이 필요합니다.');
  }
  final request = await client.postUrl(
    project.replace(path: '/rest/v1/rpc/synthetic_alert_create'),
  );
  request.followRedirects = false;
  request.headers.set('apikey', publishableKey);
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer ${session.accessToken}',
  );
  request.headers.set('Content-Profile', 'api');
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.add(
    utf8.encode(
      jsonEncode({
        'p_patient_id': syntheticPatientId,
        'p_risk_category': candidate.category,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );
  final response = await request.close();
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > 4096) {
      throw const FormatException('보조 alert 응답이 너무 큽니다.');
    }
    bytes.addAll(chunk);
  }
  if (response.statusCode != HttpStatus.ok || !session.usable(DateTime.now())) {
    throw const FormatException('보조 alert 생성 상태를 확인하지 못했습니다.');
  }
  final rows = jsonDecode(utf8.decode(bytes));
  if (rows is! List ||
      rows.length != 1 ||
      rows.single is! Map<String, dynamic>) {
    throw const FormatException('보조 alert 생성 결과가 올바르지 않습니다.');
  }
  final row = rows.single as Map<String, dynamic>;
  if (row['authorized'] != true ||
      row['alert_id'] is! String ||
      !_uuid.hasMatch(row['alert_id'] as String) ||
      row['state'] != 'created') {
    throw const FormatException('보조 alert 기록 생성을 확인하지 못했습니다.');
  }
  return SyntheticAlertCreated(row['alert_id'] as String);
}
