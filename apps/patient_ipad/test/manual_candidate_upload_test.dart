import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/main.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fake_recorder.dart';

void main() {
  testWidgets('only a confirmed own-voice candidate enables manual upload', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    final fake = FakeRecorderPlatform();
    RecordPlatform.instance = fake;
    fake.permission.complete(true);
    try {
      await tester.pumpWidget(const PatientMicDemo());
      await tester.tap(find.text('마이크 시험 시작'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(fake.starts, 1);

      fake.feedCandidate();
      await tester.pump();
      final upload = find.widgetWithText(FilledButton, '자가 음성 후보 한 건 보내기');
      expect(tester.widget<FilledButton>(upload).onPressed, isNull);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      fake.feedCandidate();
      await tester.pump();
      expect(tester.widget<FilledButton>(upload).onPressed, isNotNull);
      await tester.enterText(
        find.byType(TextField).first,
        'http://example.com/other',
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 32);
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        fake.stops,
        1,
        reason: 'mic must stop before the manual send path',
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      RecordPlatform.instance = original;
    }
  });
}
