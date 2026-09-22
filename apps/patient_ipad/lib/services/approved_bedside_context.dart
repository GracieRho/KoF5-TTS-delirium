import 'dart:convert';
import 'dart:io';

import '../device_anonymous_auth.dart';
import '../models/approved_bedside_data.dart';
import '../models/bedside_context.dart';
import '../models/schedule_item.dart';

Future<ApprovedBedsideData?> fetchApprovedBedsideData(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session,
  DevicePairContext pair, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (!session.usable(DateTime.now()) || pair.patientId != syntheticPatientId) {
    throw const FormatException('확인된 현재 입원 기기 연결이 필요합니다.');
  }
  final endpoint = project.replace(
    path: '/rest/v1/hospital_context_current',
    queryParameters: {
      'patient_id': 'eq.${pair.patientId}',
      'select': 'patient_id,encounter_id,category,content',
      'limit': '20',
    },
  );
  final request = await client.getUrl(endpoint);
  request.followRedirects = false;
  request.headers.set('apikey', publishableKey);
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer ${session.accessToken}',
  );
  request.headers.set('Accept-Profile', 'api');
  final response = await request.close();
  final body = <int>[];
  await for (final chunk in response) {
    if (body.length + chunk.length > 16_000) {
      throw const FormatException('병실 안내 응답이 너무 큽니다.');
    }
    body.addAll(chunk);
  }
  final decoded = jsonDecode(utf8.decode(body));
  if (response.statusCode != HttpStatus.ok ||
      decoded is! List ||
      decoded.length > 20) {
    throw const FormatException('승인된 병실 안내를 확인하지 못했습니다.');
  }

  final facts = <String, List<String>>{};
  for (final row in decoded) {
    if (row is! Map<String, dynamic> ||
        row['patient_id'] != pair.patientId ||
        row['category'] is! String ||
        row['content'] is! String) {
      throw const FormatException('병실 안내 형식이 올바르지 않습니다.');
    }
    final category = row['category'] as String;
    final content = row['content'] as String;
    final encounter = row['encounter_id'];
    if (!{
          'hospital',
          'ward',
          'room',
          'test_schedule',
          'visit_schedule',
        }.contains(category) ||
        content.trim().isEmpty ||
        content.length > 200 ||
        (category == 'hospital'
            ? encounter != null && encounter != pair.encounterId
            : encounter != pair.encounterId)) {
      throw const FormatException('현재 입원의 승인된 병실 안내가 아닙니다.');
    }
    facts.putIfAbsent(category, () => []).add(content);
  }

  final hospital = facts['hospital'] ?? const [];
  final ward = facts['ward'] ?? const [];
  final room = facts['room'] ?? const [];
  if (hospital.length != 1 || ward.length != 1 || room.length != 1) {
    return null;
  }
  final schedule = <ScheduleItem>[
    for (final content in facts['test_schedule'] ?? const <String>[])
      ScheduleItem(timeLabel: '검사 일정', title: content),
    for (final content in facts['visit_schedule'] ?? const <String>[])
      ScheduleItem(timeLabel: '면회 일정', title: content),
  ];
  return ApprovedBedsideData(
    context: BedsideContext(
      hospital: hospital.single,
      ward: ward.single,
      room: room.single,
    ),
    schedule: schedule,
  );
}
