import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/main_debug.dart';
import 'package:kof5_patient/models/bedside_context.dart';
import 'package:kof5_patient/models/bedside_data.dart';
import 'package:kof5_patient/models/bedside_status.dart';
import 'package:kof5_patient/models/schedule_item.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Future<ByteData> font(String name) async =>
        ByteData.sublistView(await File('assets/fonts/$name').readAsBytes());
    await (FontLoader('Pretendard')
          ..addFont(font('Pretendard-Regular.otf'))
          ..addFont(font('Pretendard-SemiBold.otf'))
          ..addFont(font('Pretendard-Bold.otf')))
        .load();
    await (FontLoader(
      'Roboto',
    )..addFont(font('Pretendard-Regular.otf'))).load();
  });

  testWidgets('capture patient bedside surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const data = BedsideData(
      context: BedsideContext(hospital: '한마음병원', ward: '5병동', room: '501호'),
      schedule: [
        ScheduleItem(timeLabel: '오전 10:00', title: '담당 의료진 회진'),
        ScheduleItem(timeLabel: '오후 3:00', title: '영상검사'),
        ScheduleItem(timeLabel: '오후 5:00', title: '보호자 면회'),
      ],
      status: BedsideStatus.waiting,
      message: '김정희님, 오늘은 9월 22일 화요일입니다.',
    );
    await tester.pumpWidget(
      PatientApp(
        data: data,
        now: () => DateTime(2026, 9, 22, 14, 35),
        startRuntime: false,
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/patient-01-bedside.png'),
    );
  });

  testWidgets('capture hidden patient debug entry', (tester) async {
    final original = RecordPlatform.instance;
    RecordPlatform.instance = FakeRecorderPlatform();
    addTearDown(() => RecordPlatform.instance = original);
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PatientMicDemo());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/patient-02-hidden-debug.png'),
    );
  });

  testWidgets('capture patient bedside portrait surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const data = BedsideData(
      context: BedsideContext(hospital: '한마음병원', ward: '5병동', room: '501호'),
      schedule: [
        ScheduleItem(timeLabel: '오전 10:00', title: '담당 의료진 회진'),
        ScheduleItem(timeLabel: '오후 3:00', title: '영상검사'),
        ScheduleItem(timeLabel: '오후 5:00', title: '보호자 면회'),
      ],
      status: BedsideStatus.waiting,
    );
    await tester.pumpWidget(
      PatientApp(
        data: data,
        now: () => DateTime(2026, 9, 22, 14, 35),
        startRuntime: false,
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/patient-03-bedside-portrait.png'),
    );
  });
}
