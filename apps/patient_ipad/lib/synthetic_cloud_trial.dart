import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

Future<SyntheticCloudReply> sendOwnVoiceCandidate(
  HttpClient client,
  Uri endpoint,
  String token,
  Uint8List pcm,
) async {
  final local = {'localhost', '127.0.0.1', '::1'}.contains(endpoint.host);
  if (endpoint.path != '/internal/synthetic/audio' ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      !(endpoint.scheme == 'https' || (local && endpoint.scheme == 'http'))) {
    throw const FormatException('HTTPS 내부 오디오 API 주소가 필요합니다.');
  }
  if (token.length < 32 || !token.runes.every((code) => code < 128)) {
    throw const FormatException('32자 이상의 내부 시험 토큰이 필요합니다.');
  }
  final wav = pcm16MonoWav(pcm);
  final request = await client.postUrl(endpoint);
  request.followRedirects = false; // Never forward the internal token to a redirect target.
  request.headers.set(HttpHeaders.contentTypeHeader, 'audio/wav');
  request.headers.set('X-Internal-Demo-Token', token);
  request.headers.set('X-Synthetic-Material', 'confirmed');
  request.add(wav);
  final response = await request.close();
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
      (decoded['reply'] != null && decoded['reply'] is! String) ||
      (decoded['audio_mp3_base64'] != null && decoded['audio_mp3_base64'] is! String)) {
    throw const FormatException('서버 음성 응답 형식이 올바르지 않습니다.');
  }
  final audio = decoded['audio_mp3_base64'] as String?;
  if (audio != null && audio.length > 2_700_000) {
    throw const FormatException('서버 음성 응답이 너무 큽니다.');
  }
  return SyntheticCloudReply(
    decoded['transcript'] as String,
    decoded['reply'] as String?,
    audio == null ? null : base64Decode(audio),
  );
}
