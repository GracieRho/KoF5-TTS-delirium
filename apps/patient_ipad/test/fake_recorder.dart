import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

class FakeRecorderPlatform extends RecordPlatform {
  final permission = Completer<bool>();
  var starts = 0;
  var stops = 0;
  var stopFails = false;
  Completer<Stream<Uint8List>>? delayedStart;

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
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<String?> stop(String recorderId) async {
    stops++;
    if (stopFails) throw StateError('native stop failed');
    return null;
  }

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
