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

  testWidgets('PCM arriving while stop awaits is discarded', (tester) async {
    fake.permission.complete(true);
    await tester.pumpWidget(const PatientMicDemo());
    await tester.tap(find.text('마이크 시험 시작'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(fake.starts, 1);

    fake.delayedStop = Completer<String?>();
    await tester.tap(find.text('시험 중단'));
    for (var i = 0; i < 20 && fake.stops == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(fake.stops, 1);
    final voice = Uint8List(3200);
    final view = ByteData.sublistView(voice);
    for (var i = 0; i < 1600; i++) {
      view.setInt16(i * 2, 3000, Endian.little);
    }
    for (var i = 0; i < 3; i++) {
      fake.audio.add(voice);
    }
    for (var i = 0; i < 7; i++) {
      fake.audio.add(Uint8List(3200));
    }
    await tester.pump();
    expect(find.textContaining('감지 · 서버 전송 없음'), findsNothing);
    fake.delayedStop!.complete(null);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('마이크 시험을 중단했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
