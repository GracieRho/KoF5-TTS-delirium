import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/models/bedside_context.dart';
import 'package:kof5_patient/models/bedside_data.dart';
import 'package:kof5_patient/models/bedside_status.dart';
import 'package:kof5_patient/models/schedule_item.dart';
import 'package:kof5_patient/widgets/surface_card.dart';

void main() {
  final now = DateTime(2026, 9, 22, 15, 7);

  testWidgets('production surface shows bedside information without controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(PatientApp(now: () => now, startRuntime: false));

    expect(find.text('오후 3:07'), findsOneWidget);
    expect(find.text('9월 22일 화요일'), findsOneWidget);
    expect(find.text('병원 정보를 확인하고 있습니다'), findsOneWidget);
    expect(find.textContaining('한마음병원'), findsNothing);
    expect(find.textContaining('501호'), findsNothing);
    expect(find.text('오늘의 일정'), findsOneWidget);
    expect(find.text('오늘 예정된 일정이 없습니다.'), findsOneWidget);
    expect(find.text('회진'), findsNothing);
    expect(find.text('병원 안내를 기다리고 있어요'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.textContaining('API'), findsNothing);
    expect(find.textContaining('토큰'), findsNothing);
    expect(find.textContaining('AI'), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(SurfaceCard), findsOneWidget);
  });

  testWidgets('compact production surface stays readable and scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const compactData = BedsideData(
      context: BedsideContext(hospital: '검증 병원', ward: '검증 병동', room: '검증 병실'),
      schedule: [
        ScheduleItem(timeLabel: '오전 8:00', title: '첫 일정'),
        ScheduleItem(timeLabel: '오전 10:00', title: '둘째 일정'),
        ScheduleItem(timeLabel: '오후 1:00', title: '셋째 일정'),
        ScheduleItem(timeLabel: '오후 3:00', title: '마지막 일정'),
      ],
      status: BedsideStatus.waiting,
    );
    await tester.pumpWidget(
      PatientApp(data: compactData, now: () => now, startRuntime: false),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('마지막 일정'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('마지막 일정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
