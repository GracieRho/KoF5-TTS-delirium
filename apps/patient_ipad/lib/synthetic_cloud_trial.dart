import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'device_anonymous_auth.dart';

class SyntheticCloudReply {
  const SyntheticCloudReply(this.transcript, this.reply, this.mp3);

  final String transcript;
  final String? reply;
  final Uint8List? mp3;
}

Uint8List pcm16MonoWav(Uint8List pcm) {
  if (pcm.isEmpty || pcm.length.isOdd || pcm.length > 16000 * 2 * 8) {
    throw const FormatException('8초 이하의 PCM16 발화 후보가 필요합니다.');
  }
  final wav = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(wav);
  wav.setRange(0, 4, ascii.encode('RIFF'));
  header.setUint32(4, 36 + pcm.length, Endian.little);
  wav.setRange(8, 16, ascii.encode('WAVEfmt '));
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  wav.setRange(36, 40, ascii.encode('data'));
  header.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}

void _checkEndpoint(Uri endpoint, String path) {
  final local = {'localhost', '127.0.0.1', '::1'}.contains(endpoint.host);
  if (endpoint.path != path ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      !(endpoint.scheme == 'https' || (local && endpoint.scheme == 'http'))) {
    throw const FormatException('HTTPS 내부 시험 API 주소가 필요합니다.');
  }
}

void _checkToken(String token) {
  if (token.length < 32 || !token.runes.every((code) => code < 128)) {
    throw const FormatException('32자 이상의 내부 시험 토큰이 필요합니다.');
  }
}

Future<SyntheticCloudReply> sendOwnVoiceCandidate(
  HttpClient client,
  Uri endpoint,
  String token,
  Uint8List pcm,
) async {
  _checkEndpoint(endpoint, '/internal/synthetic/audio');
  _checkToken(token);
  final wav = pcm16MonoWav(pcm);
  final request = await client.postUrl(endpoint);
  request.followRedirects =
      false; // Never forward the internal token to a redirect target.
  request.headers.set(HttpHeaders.contentTypeHeader, 'audio/wav');
  request.headers.set('X-Internal-Demo-Token', token);
  request.headers.set('X-Synthetic-Material', 'confirmed');
  request.add(wav);
  final response = await request.close();
  return _readReply(response);
}

Future<SyntheticCloudReply> sendOwnVoiceText(
  HttpClient client,
  Uri endpoint,
  String token,
  String transcript,
  String label,
) async {
  return _sendText(
    client,
    endpoint,
    token,
    transcript,
    label,
    '/internal/synthetic/text',
  );
}

Future<SyntheticCloudReply> sendPairedOwnVoiceText(
  HttpClient client,
  Uri endpoint,
  String token,
  String transcript,
  String label,
  String deviceJwt,
  String patientId, {
  String? allowedOriginForTest,
}) async {
  const configuredOrigin = String.fromEnvironment(
    'KOF5_PAIRED_SYNTHETIC_API_ORIGIN',
  );
  final allowedOrigin = allowedOriginForTest ?? configuredOrigin;
  final origin = Uri.tryParse(allowedOrigin);
  final localTest =
      allowedOriginForTest != null &&
      origin != null &&
      {'127.0.0.1', 'localhost', '::1'}.contains(origin.host) &&
      origin.scheme == 'http';
  if (origin == null ||
      origin.toString() != allowedOrigin ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      origin.path.isNotEmpty ||
      !(origin.scheme == 'https' || localTest) ||
      endpoint.origin != origin.origin) {
    throw const FormatException('설정된 합성 시험 API 원점이 필요합니다.');
  }
  final parts = deviceJwt.split('.');
  if (patientId != syntheticPatientId ||
      deviceJwt.length > 8192 ||
      parts.length != 3 ||
      parts.any((part) => !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(part))) {
    throw const FormatException('확인된 합성 기기 로그인과 연결이 필요합니다.');
  }
  return _sendText(
    client,
    endpoint,
    token,
    transcript,
    label,
    '/internal/synthetic/paired/$patientId/text',
    deviceJwt,
  );
}

Future<SyntheticCloudReply> _sendText(
  HttpClient client,
  Uri endpoint,
  String token,
  String transcript,
  String label,
  String path, [
  String? deviceJwt,
]) async {
  _checkEndpoint(endpoint, path);
  _checkToken(token);
  if (transcript.trim().isEmpty ||
      transcript.length > 500 ||
      !{'DIRECTED', 'AMBIENT', 'UNCERTAIN'}.contains(label)) {
    throw const FormatException('짧은 기기 내 전사와 활성화 판정이 필요합니다.');
  }
  final request = await client.postUrl(endpoint);
  request.followRedirects = false;
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.headers.set('X-Internal-Demo-Token', token);
  request.headers.set('X-Synthetic-Material', 'confirmed');
  if (deviceJwt != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $deviceJwt');
  }
  request.add(
    utf8.encode(jsonEncode({'transcript': transcript, 'label': label})),
  );
  return _readReply(await request.close());
}

Future<SyntheticCloudReply> _readReply(HttpClientResponse response) async {
  final body = <int>[];
  await for (final chunk in response) {
    if (body.length + chunk.length > 4_000_000) {
      throw const FormatException('서버 응답이 너무 큽니다.');
    }
    body.addAll(chunk);
  }
  if (response.statusCode != HttpStatus.ok) {
    throw FormatException('서버 요청이 거절되었습니다 (${response.statusCode}).');
  }
  final decoded = jsonDecode(utf8.decode(body));
  if (decoded is! Map<String, dynamic> ||
      decoded['transcript'] is! String ||
      (decoded['transcript'] as String).length > 500 ||
      (decoded['reply'] != null && decoded['reply'] is! String) ||
      (decoded['reply'] is String &&
          (decoded['reply'] as String).length > 1000) ||
      (decoded['audio_mp3_base64'] != null &&
          decoded['audio_mp3_base64'] is! String)) {
    throw const FormatException('서버 음성 응답 형식이 올바르지 않습니다.');
  }
  final audio = decoded['audio_mp3_base64'] as String?;
  if (audio != null && audio.length > 2_700_000) {
    throw const FormatException('서버 음성 응답이 너무 큽니다.');
  }
  final mp3 = audio == null ? null : base64Decode(audio);
  if (mp3 != null && mp3.length > 2_000_000) {
    throw const FormatException('서버 음성 응답이 너무 큽니다.');
  }
  return SyntheticCloudReply(
    decoded['transcript'] as String,
    decoded['reply'] as String?,
    mp3,
  );
}
