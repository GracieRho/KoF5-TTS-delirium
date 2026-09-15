import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

class FakeRecorderPlatform extends RecordPlatform {
  final permission = Completer<bool>();
  final audio = StreamController<Uint8List>.broadcast();
  var starts = 0;
  var stops = 0;
  var stopFails = false;
  Completer<Stream<Uint8List>>? delayedStart;
  Completer<String?>? delayedStop;

  void feedCandidate() {
    final voice = Uint8List(3200);
    final view = ByteData.sublistView(voice);
    for (var index = 0; index < 1600; index++) {
      view.setInt16(index * 2, 3000, Endian.little);
    }
    for (var index = 0; index < 3; index++) {
      audio.add(voice);
    }
    for (var index = 0; index < 7; index++) {
      audio.add(Uint8List(3200));
    }
  }

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) =>
      permission.future;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    starts++;
    if (delayedStart case final pending?) return pending.future;
    return audio.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    stops++;
    if (delayedStop case final pending?) return pending.future;
    if (stopFails) throw StateError('native stop failed');
    return null;
  }

  @override
  Future<void> dispose(String recorderId) => audio.close();

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
