import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/speech_candidate.dart';

Uint8List frame(int value) {
  final bytes = Uint8List(3200); // 100 ms, 16 kHz mono PCM16.
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < 1600; i++) {
    view.setInt16(i * 2, value, Endian.little);
  }
  return bytes;
}

void main() {
  test('short noise is ignored; sustained speech includes bounded preroll', () {
    final detector = SpeechCandidateDetector();
    for (var i = 0; i < 15; i++) {
      expect(detector.add(frame(0)), isNull);
    }
    expect(detector.add(frame(3000)), isNull); // One 100 ms burst is too short.
    for (var i = 0; i < 10; i++) {
      expect(detector.add(frame(0)), isNull);
    }
    for (var i = 0; i < 3; i++) {
      expect(detector.add(frame(3000)), isNull);
    }
    for (var i = 0; i < 8; i++) {
      expect(detector.add(frame(0)), isNull); // An 800 ms pause stays in the turn.
    }
    final candidate = detector.add(frame(0)); // End at 900 ms by default.
    expect(candidate, isNotNull);
    expect(candidate!.length, lessThanOrEqualTo(3200 * 20));
    expect(candidate.length, greaterThan(3200 * 8));
    expect(detector.add(frame(0)), isNull); // Previous PCM was cleared.
    expect(
      detector.add(Uint8List(64000)),
      isNull,
    ); // Oversized callback is discarded.
  });
}
