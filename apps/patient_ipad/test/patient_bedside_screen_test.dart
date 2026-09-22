import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';

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
    expect(find.textContaining('한마음병원'), findsOneWidget);
    expect(find.text('오늘의 일정'), findsOneWidget);
    expect(find.text('회진'), findsOneWidget);
    expect(find.text('안내를 듣고 있어요'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.textContaining('API'), findsNothing);
    expect(find.textContaining('토큰'), findsNothing);
    expect(find.textContaining('AI'), findsNothing);
  });

  testWidgets('compact production surface stays readable and scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(PatientApp(now: () => now, startRuntime: false));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('검사 예정'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('검사 예정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
