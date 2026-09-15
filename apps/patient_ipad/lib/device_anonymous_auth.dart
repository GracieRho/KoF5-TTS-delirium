import 'dart:convert';
import 'dart:io';

const syntheticPatientId = '00000000-0000-4000-8000-000000000975';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class AnonymousDeviceSession {
  const AnonymousDeviceSession(this.userId, this.accessToken, this.expiresAt);

  final String userId;
  final String accessToken;
  final DateTime expiresAt;

  bool usable(DateTime now) =>
      expiresAt.isAfter(now.add(const Duration(seconds: 60)));
}

class DevicePairContext {
  const DevicePairContext(this.patientId, this.encounterId);

  final String patientId;
  final String encounterId;
}

void checkDedicatedSupabase(
  Uri project,
  String publishableKey, {
  bool allowEphemeralLoopbackForTest = false,
}) {
  const pinnedProject = String.fromEnvironment('KOF5_DEVICE_SUPABASE_URL');
  final local = {'localhost', '127.0.0.1', '::1'}.contains(project.host);
  final remote =
      RegExp(r'^[a-z0-9]{20}\.supabase\.co$').hasMatch(project.host) &&
      project.host != 'dqjplezbvtjbsunabxbg.supabase.co' &&
      !project.hasPort &&
      project.origin == pinnedProject;
  if (project.userInfo.isNotEmpty ||
      project.hasQuery ||
      project.hasFragment ||
      (project.path.isNotEmpty && project.path != '/') ||
      !(project.scheme == 'https' && remote ||
          project.scheme == 'http' &&
              local &&
              (project.port == 54341 || allowEphemeralLoopbackForTest)) ||
      !publishableKey.startsWith('sb_publishable_') ||
      publishableKey.length < 30 ||
      publishableKey.length > 256 ||
      !publishableKey.runes.every((code) => code > 32 && code < 127)) {
    throw const FormatException('전용 Supabase 주소와 publishable 키가 필요합니다.');
  }
}

Future<AnonymousDeviceSession> signInAnonymousDevice(
  HttpClient client,
  Uri project,
  String publishableKey, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  final request = await client.postUrl(
    project.replace(path: '/auth/v1/signup'),
  );
  request.followRedirects = false;
  request.headers.set('apikey', publishableKey);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.add(
    utf8.encode(
      jsonEncode({
        'data': <String, dynamic>{},
        'gotrue_meta_security': {'captcha_token': null},
      }),
    ),
  );
  final response = await request.close();
  final data = await _readJson(response, 16_000);
  if (data is! Map<String, dynamic> || response.statusCode != HttpStatus.ok) {
    throw const FormatException('익명 기기 로그인을 확인하지 못했습니다.');
  }
  final user = data['user'];
  final token = data['access_token'];
  final expiry = data['expires_at'];
  final now = DateTime.now();
  if (user is! Map<String, dynamic> ||
      user['id'] is! String ||
      !_uuid.hasMatch(user['id'] as String) ||
      user['is_anonymous'] != true ||
      data['token_type']?.toString().toLowerCase() != 'bearer' ||
      token is! String ||
      token.length > 8192 ||
      expiry is! int) {
    throw const FormatException('익명 기기 로그인 응답 형식이 올바르지 않습니다.');
  }
  final parts = token.split('.');
  if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
    throw const FormatException('기기 JWT 형식이 올바르지 않습니다.');
  }
  final claims = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  );
  if (claims is! Map<String, dynamic> ||
      claims['sub'] != user['id'] ||
      claims['role'] != 'authenticated' ||
      claims['is_anonymous'] != true ||
      claims['exp'] is! int ||
      (claims['exp'] as int) != expiry) {
    throw const FormatException('익명 기기 JWT가 로그인 응답과 맞지 않습니다.');
  }
  final serverExpiry = DateTime.fromMillisecondsSinceEpoch(expiry * 1000);
  final maxLocalExpiry = now.add(const Duration(hours: 1));
  final expiresAt = serverExpiry.isBefore(maxLocalExpiry)
      ? serverExpiry
      : maxLocalExpiry;
  final session = AnonymousDeviceSession(
    user['id'] as String,
    token,
    expiresAt,
  );
  if (!session.usable(now)) {
    throw const FormatException('기기 JWT의 유효 시간이 부족합니다.');
  }
  return session; // Refresh token is deliberately never stored.
}

Future<DevicePairContext> confirmSyntheticDevicePair(
  HttpClient client,
  Uri project,
  String publishableKey,
  AnonymousDeviceSession session, {
  bool allowEphemeralLoopbackForTest = false,
}) async {
  checkDedicatedSupabase(
    project,
    publishableKey,
    allowEphemeralLoopbackForTest: allowEphemeralLoopbackForTest,
  );
  if (!session.usable(DateTime.now())) {
    throw const FormatException('기기 로그인 시간이 끝났습니다.');
  }
  final endpoint = project.replace(
    path: '/rest/v1/patient_device_context',
    queryParameters: {'select': 'patient_id,encounter_id', 'limit': '2'},
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
  final rows = await _readJson(response, 4096);
  if (response.statusCode != HttpStatus.ok ||
      rows is! List ||
      rows.length != 1) {
    throw const FormatException('병원에서 확인한 합성 기기 연결이 없습니다.');
  }
  final row = rows.single;
  if (row is! Map<String, dynamic> ||
      row['patient_id'] != syntheticPatientId ||
      row['encounter_id'] is! String ||
      !_uuid.hasMatch(row['encounter_id'] as String)) {
    throw const FormatException('합성 기기 연결 자료가 올바르지 않습니다.');
  }
  return DevicePairContext(
    row['patient_id'] as String,
    row['encounter_id'] as String,
  );
}

Future<dynamic> _readJson(HttpClientResponse response, int maxBytes) async {
  final body = <int>[];
  await for (final chunk in response) {
    if (body.length + chunk.length > maxBytes) {
      throw const FormatException('기기 인증 응답이 너무 큽니다.');
    }
    body.addAll(chunk);
  }
  return jsonDecode(utf8.decode(body));
}
