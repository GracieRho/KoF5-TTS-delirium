import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

class FakeRecorderPlatform extends RecordPlatform {
  final permission = Completer<bool>();
  var starts = 0;
  var stops = 0;
  var stopFails = false;

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

void main() {
  late RecordPlatform original;
  late FakeRecorderPlatform fake;

  setUp(() {
    original = RecordPlatform.instance;
    fake = FakeRecorderPlatform();
    RecordPlatform.instance = fake;
  });
  tearDown(() => RecordPlatform.instance = original);

  testWidgets('permission completing after background never starts mic', (
    tester,
  ) async {
    await tester.pumpWidget(const PatientMicDemo());
    await tester.tap(find.text('마이크 시험 시작'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fake.permission.complete(true);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(fake.starts, 0);
    expect(find.text('마이크 준비 중'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed native stop locks restart and reports uncertainty', (
    tester,
  ) async {
    fake.permission.complete(true);
    await tester.pumpWidget(const PatientMicDemo());
    await tester.tap(find.text('마이크 시험 시작'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(fake.starts, 1);
    fake.stopFails = true;
    await tester.tap(find.text('시험 중단'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(fake.stops, 1);
    expect(find.textContaining('마이크 중단을 확인하지 못했습니다'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
