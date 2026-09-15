import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'device_anonymous_auth.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class DueHospitalMessage {
  const DueHospitalMessage(this.id, this.approvedText, this.dueAt);

  final String id;
  final String approvedText;
  final DateTime dueAt;
}

Future<List<String>> listSyntheticDueHospitalMessageIds(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  final rows = await _rpc(
    client,
    project,
    publishableKey,
    session,
    'synthetic_due_hospital_message_ids',
    {'_patient_id': syntheticPatientId},
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (rows.length > 3) throw const FormatException('합성 병원 메시지 목록이 너무 큽니다.');
  final ids = <String>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic> ||
        row['message_id'] is! String ||
        row['due_at'] is! String ||
        !_uuid.hasMatch(row['message_id'] as String) ||
        DateTime.tryParse(row['due_at'] as String) == null ||
        ids.contains(row['message_id'])) {
      throw const FormatException('승인된 합성 메시지 목록을 확인하지 못했습니다.');
    }
    ids.add(row['message_id'] as String);
  }
  return ids;
}

Future<DueHospitalMessage> confirmSyntheticDueHospitalMessage(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session,
  String messageId, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  if (!_uuid.hasMatch(messageId)) {
    throw const FormatException('병원 메시지 ID가 올바르지 않습니다.');
  }
  final rows = await _rpc(
    client,
    project,
    publishableKey,
    session,
    'synthetic_due_hospital_message',
    {'_patient_id': syntheticPatientId, '_message_id': messageId},
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (rows.length != 1 || rows.single is! Map<String, dynamic>) {
    throw const FormatException('승인된 합성 병원 메시지를 확인하지 못했습니다.');
  }
  final row = rows.single as Map<String, dynamic>;
  final text = row['approved_text'];
  final due = row['due_at'];
  final dueAt = due is String ? DateTime.tryParse(due) : null;
  if (row['authorized'] != true ||
      row['message_id'] != messageId ||
      text is! String ||
      text.trim().isEmpty ||
      text.length > 200 ||
      dueAt == null) {
    throw const FormatException('현재 전달 가능한 직원 승인 원문이 아닙니다.');
  }
  return DueHospitalMessage(messageId, text, dueAt);
}

Future<bool> completeSyntheticHospitalPlayback(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session,
  String messageId,
  String attemptId, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (!_uuid.hasMatch(messageId) ||
      !_uuidV4.hasMatch(attemptId) ||
      !session.usable(DateTime.now())) {
    throw const FormatException('현재 기기 재생 완료 시도가 필요합니다.');
  }
  final request = await client.postUrl(
    project.replace(
      path: '/rest/v1/rpc/synthetic_hospital_message_playback_complete',
    ),
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
        'p_message_id': messageId,
        'p_attempt_id': attemptId,
      }),
    ),
  );
  final response = await request.close();
  final body = await _read(response, 4096);
  if (response.statusCode != HttpStatus.ok ||
      !session.usable(DateTime.now()) ||
      body is! bool) {
    throw const FormatException('병원 메시지 전달 확인 결과가 불확실합니다.');
  }
  return body;
}

Future<List<dynamic>> _rpc(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session,
  String name,
  Map<String, String> params, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (!session.usable(DateTime.now())) {
    throw const FormatException('기기 JWT 시간이 끝났습니다.');
  }
  final request = await client.postUrl(
    project.replace(path: '/rest/v1/rpc/$name'),
  );
  request.followRedirects = false;
  request.headers.set('apikey', publishableKey);
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer ${session.accessToken}',
  );
  request.headers.set('Content-Profile', 'api');
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.add(utf8.encode(jsonEncode(params)));
  final response = await request.close();
  final body = await _read(response, 4096);
  if (response.statusCode != HttpStatus.ok ||
      !session.usable(DateTime.now()) ||
      body is! List) {
    throw const FormatException('기기 권한과 병원 메시지 응답을 확인하지 못했습니다.');
  }
  return body;
}

Future<Uint8List> synthesizeSyntheticHospitalMessage(
  HttpClient client,
  Uri endpoint,
  String demoToken,
  AnonymousDeviceSession session,
  DueHospitalMessage message, {
  String? allowedOriginForTest,
}) async {
  const configuredOrigin = String.fromEnvironment(
    'KOF5_PAIRED_SYNTHETIC_API_ORIGIN',
  );
  final allowed = allowedOriginForTest ?? configuredOrigin;
  final origin = Uri.tryParse(allowed);
  final localTest =
      allowedOriginForTest != null &&
      origin != null &&
      {'127.0.0.1', 'localhost', '::1'}.contains(origin.host) &&
      origin.scheme == 'http';
  if (origin == null ||
      origin.toString() != allowed ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      origin.path.isNotEmpty ||
      !(origin.scheme == 'https' || localTest) ||
      endpoint.origin != origin.origin ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      endpoint.path !=
          '/internal/synthetic/paired/$syntheticPatientId/message/${message.id}/audio' ||
      !_uuid.hasMatch(message.id) ||
      !session.usable(DateTime.now()) ||
      demoToken.length < 32 ||
      !demoToken.runes.every((code) => code > 32 && code < 127)) {
    throw const FormatException('확인된 합성 병원 음성 시험 API가 필요합니다.');
  }
  final request = await client.postUrl(endpoint);
  request.followRedirects = false;
  request.headers.set('X-Internal-Demo-Token', demoToken);
  request.headers.set('X-Synthetic-Material', 'confirmed');
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer ${session.accessToken}',
  );
  final response = await request.close();
  final body = await _read(response, 2_700_000);
  if (response.statusCode != HttpStatus.ok ||
      !session.usable(DateTime.now()) ||
      body is! Map<String, dynamic> ||
      body['approved_text'] != message.approvedText ||
      body['audio_mp3_base64'] is! String) {
    throw const FormatException('병원 원문과 음성 응답을 확인하지 못했습니다.');
  }
  final mp3 = base64Decode(body['audio_mp3_base64'] as String);
  if (mp3.isEmpty || mp3.length > 2_000_000) {
    throw const FormatException('병원 음성 응답 크기가 올바르지 않습니다.');
  }
  return mp3;
}

Future<dynamic> _read(HttpClientResponse response, int maxBytes) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const FormatException('병원 메시지 응답이 너무 큽니다.');
    }
    bytes.addAll(chunk);
  }
  return jsonDecode(utf8.decode(bytes));
}
