import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });

  testWidgets('late native start with failed stop stays locked', (
    tester,
  ) async {
    fake.permission.complete(true);
    fake.delayedStart = Completer<Stream<Uint8List>>();
    await tester.pumpWidget(const PatientMicDemo());
    await tester.tap(find.text('마이크 시험 시작'));
    for (var i = 0; i < 20 && fake.starts == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(fake.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fake.stopFails = true;
    fake.delayedStart!.complete(const Stream<Uint8List>.empty());
    for (var i = 0; i < 20 && fake.stops == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(fake.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('마이크 중단을 확인하지 못했습니다'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });
}
