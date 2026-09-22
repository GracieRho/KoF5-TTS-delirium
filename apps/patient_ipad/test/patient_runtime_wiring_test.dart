import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/app/patient_app.dart';
import 'package:kof5_patient/controllers/patient_runtime_controller.dart';
import 'package:kof5_patient/models/approved_bedside_data.dart';
import 'package:kof5_patient/models/bedside_context.dart';
import 'package:kof5_patient/models/schedule_item.dart';
import 'package:kof5_patient/services/runtime_hospital_message.dart';

void main() {
  testWidgets('production app polls, plays a message, and returns to waiting', (
    tester,
  ) async {
    final playback = Completer<bool>();
    var polls = 0;
    final runtime = PatientRuntimeController(
      pollHospital: () async {
        polls++;
        return polls == 1
            ? RuntimeHospitalMessage(
                id: '00000000-0000-4000-8000-000000000903',
                text: '오후 3시에 검사가 있습니다.',
                audio: Uint8List.fromList([1, 2, 3]),
              )
            : null;
      },
      playMessage: (_) => playback.future,
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(PatientApp(runtime: runtime));
    await _until(
      tester,
      () => find.text('안내 말씀을 들려드리고 있어요').evaluate().isNotEmpty,
    );

    expect(find.text('안내 말씀을 들려드리고 있어요'), findsOneWidget);
    expect(find.text('오후 3시에 검사가 있습니다.'), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);

    playback.complete(true);
    await _until(
      tester,
      () => find.text('병원 안내를 기다리고 있어요').evaluate().isNotEmpty,
    );

    expect(find.text('병원 안내를 기다리고 있어요'), findsOneWidget);
    expect(polls, 1);

    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });

  testWidgets('failed refresh clears previously verified bedside orientation', (
    tester,
  ) async {
    var loads = 0;
    final runtime = PatientRuntimeController(
      loadBedsideData: () async {
        loads++;
        if (loads > 1) throw const FormatException('stale');
        return const ApprovedBedsideData(
          context: BedsideContext(
            hospital: '승인 병원',
            ward: '승인 병동',
            room: '승인 병실',
          ),
          schedule: [ScheduleItem(timeLabel: '검사 일정', title: '승인 검사 내용')],
        );
      },
      pollHospital: () async => null,
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(PatientApp(runtime: runtime));
    await _until(
      tester,
      () => find.textContaining('승인 병원').evaluate().isNotEmpty,
    );
    expect(find.text('승인 검사 내용'), findsOneWidget);

    await runtime.refresh();
    await tester.pump();

    expect(find.textContaining('승인 병원'), findsNothing);
    expect(find.text('승인 검사 내용'), findsNothing);
    expect(find.text('병원 정보를 확인하고 있습니다'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 30 && !ready(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
