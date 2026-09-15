import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:kof5_patient/synthetic_cloud_trial.dart';

import 'fake_recorder.dart';

Future<void> startMockPlaybackTrial(
  WidgetTester tester,
  FakeRecorderPlatform fake,
  Future<SyntheticCloudReply> Function(HttpClient, Uri, String, Uint8List)
  cloudTrial,
) async {
  await tester.pumpWidget(PatientMicDemo(cloudTrial: cloudTrial));
  await tester.tap(find.text('마이크 시험 시작'));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  expect(fake.starts, 1);
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  fake.feedCandidate();
  await tester.pump();
  await tester.enterText(
    find.byType(TextField).first,
    'https://example.com/internal/synthetic/audio',
  );
  await tester.enterText(find.byType(TextField).last, 'x' * 32);
  final upload = find.widgetWithText(FilledButton, '자가 음성 후보 한 건 보내기');
  expect(tester.widget<FilledButton>(upload).onPressed, isNotNull);
  await tester.ensureVisible(upload);
  await tester.tap(upload);
  for (var index = 0; index < 20 && fake.stops == 0; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(fake.stops, 1);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}
