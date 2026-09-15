import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/device_anonymous_auth.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';

void main() {
  test(
    'manual own-voice candidate reaches only the guarded WAV endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<(String?, String?, List<int>)>();
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (body, chunk) => body..addAll(chunk),
        );
        seen.complete((
          request.headers.value('X-Internal-Demo-Token'),
          request.headers.value('X-Synthetic-Material'),
          bytes,
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'transcript': '수민아?',
            'reply': '응, 왜?',
            'audio_mp3_base64': base64Encode([1, 2, 3]),
          }),
        );
        await request.response.close();
      });
      final client = HttpClient();
      try {
        final reply = await sendOwnVoiceCandidate(
          client,
          Uri.parse('http://127.0.0.1:${server.port}/internal/synthetic/audio'),
          'x' * 32,
          Uint8List.fromList([0, 0, 1, 0]),
        );
        final (token, declaration, wav) = await seen.future;
        expect(token, 'x' * 32);
        expect(declaration, 'confirmed');
        expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
        expect(
          ByteData.sublistView(
            Uint8List.fromList(wav),
          ).getUint32(40, Endian.little),
          4,
        );
        expect((reply.transcript, reply.reply), ('수민아?', '응, 왜?'));
        expect(reply.mp3, [1, 2, 3]);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test(
    'remote HTTP, wrong path and short token fail before sending audio',
    () async {
      final client = HttpClient();
      try {
        for (final endpoint in [
          Uri.parse('http://example.com/internal/synthetic/audio'),
          Uri.parse('https://example.com/other'),
        ]) {
          await expectLater(
            sendOwnVoiceCandidate(client, endpoint, 'x' * 32, Uint8List(4)),
            throwsFormatException,
          );
        }
        await expectLater(
          sendOwnVoiceCandidate(
            client,
            Uri.parse('https://example.com/internal/synthetic/audio'),
            'short',
            Uint8List(4),
          ),
          throwsFormatException,
        );
      } finally {
        client.close(force: true);
      }
    },
  );

  test('on-device transcript sends JSON text and no candidate audio', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<(String?, String?, String, Object?)>();
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        <int>[],
        (body, chunk) => body..addAll(chunk),
      );
      seen.complete((
        request.headers.contentType?.mimeType,
        request.headers.value('X-Internal-Demo-Token'),
        request.uri.path,
        jsonDecode(utf8.decode(bytes)),
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'transcript': '수민아?',
          'reply': '응, 왜?',
          'audio_mp3_base64': base64Encode([1, 2, 3]),
        }),
      );
      await request.response.close();
    });
    final client = HttpClient();
    try {
      final reply = await sendOwnVoiceText(
        client,
        Uri.parse('http://127.0.0.1:${server.port}/internal/synthetic/text'),
        'x' * 32,
        '수민아?',
        'DIRECTED',
      );
      final (mime, token, path, body) = await seen.future;
      expect(
        (mime, token, path),
        ('application/json', 'x' * 32, '/internal/synthetic/text'),
      );
      expect(body, {'transcript': '수민아?', 'label': 'DIRECTED'});
      expect(reply.mp3, [1, 2, 3]);
      await expectLater(
        sendOwnVoiceText(
          client,
          Uri.parse('http://example.com/internal/synthetic/text'),
          'x' * 32,
          '수민아?',
          'DIRECTED',
        ),
        throwsFormatException,
      );
      await expectLater(
        sendOwnVoiceText(
          client,
          Uri.parse('https://example.com/internal/synthetic/audio'),
          'x' * 32,
          '수민아?',
          'DIRECTED',
        ),
        throwsFormatException,
      );
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test('paired synthetic text sends only JSON with device Bearer', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<(String, String?, String?, String?, Object?)>();
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.complete((
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        request.headers.value('X-Internal-Demo-Token'),
        request.headers.contentType?.mimeType,
        jsonDecode(body),
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'transcript': '수민아?',
          'reply': null,
          'audio_mp3_base64': null,
        }),
      );
      await request.response.close();
    });
    final client = HttpClient();
    const jwt = 'header.payload.signature';
    try {
      final endpoint = Uri.parse(
        'http://127.0.0.1:${server.port}/internal/synthetic/paired/$syntheticPatientId/text',
      );
      final reply = await sendPairedOwnVoiceText(
        client,
        endpoint,
        'x' * 32,
        '수민아?',
        'DIRECTED',
        jwt,
        syntheticPatientId,
        allowedOriginForTest: 'http://127.0.0.1:${server.port}',
      );
      final (path, bearer, demoToken, mime, body) = await seen.future;
      expect(path, '/internal/synthetic/paired/$syntheticPatientId/text');
      expect(bearer, 'Bearer $jwt');
      expect((demoToken, mime), ('x' * 32, 'application/json'));
      expect(body, {'transcript': '수민아?', 'label': 'DIRECTED'});
      expect(reply.mp3, isNull);
      await expectLater(
        sendPairedOwnVoiceText(
          client,
          endpoint,
          'x' * 32,
          '수민아?',
          'DIRECTED',
          jwt,
          '00000000-0000-4000-8000-000000000976',
          allowedOriginForTest: 'http://127.0.0.1:${server.port}',
        ),
        throwsFormatException,
      );
      await expectLater(
        sendPairedOwnVoiceText(
          client,
          Uri.parse(
            'http://example.com/internal/synthetic/paired/$syntheticPatientId/text',
          ),
          'x' * 32,
          '수민아?',
          'DIRECTED',
          jwt,
          syntheticPatientId,
          allowedOriginForTest: 'http://127.0.0.1:${server.port}',
        ),
        throwsFormatException,
      );
      await expectLater(
        sendPairedOwnVoiceText(
          client,
          endpoint,
          'x' * 32,
          '수민아?',
          'DIRECTED',
          jwt,
          syntheticPatientId,
        ),
        throwsFormatException,
      );
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}
