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
