import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/app/patient_app.dart';
import 'package:kof5_patient/controllers/patient_runtime_controller.dart';
import 'package:kof5_patient/services/runtime_hospital_message.dart';

void main() {
  testWidgets('production app starts listening, plays a message, and resumes', (
    tester,
  ) async {
    final audio = StreamController<Uint8List>.broadcast();
    final playback = Completer<bool>();
    var starts = 0;
    var stops = 0;
    var polls = 0;
    final runtime = PatientRuntimeController(
      startCapture: () async {
        starts++;
        return audio.stream;
      },
      stopCapture: () async => stops++,
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
    addTearDown(() {
      runtime.dispose();
      audio.close();
    });

    await tester.pumpWidget(PatientApp(runtime: runtime));
    await _until(tester, () => starts == 1 && stops == 1);

    expect(find.text('안내 말씀을 들려드리고 있어요'), findsOneWidget);
    expect(find.text('오후 3시에 검사가 있습니다.'), findsOneWidget);
    expect(find.byType(ButtonStyleButton), findsNothing);

    playback.complete(true);
    await _until(tester, () => starts == 2);

    expect(find.text('안내를 듣고 있어요'), findsOneWidget);
    expect(stops, 1);

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
