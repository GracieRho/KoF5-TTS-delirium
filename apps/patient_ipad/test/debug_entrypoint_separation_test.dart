import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production entrypoint has no debug route or diagnostic imports', () {
    final production = File('lib/main.dart').readAsStringSync();
    final debug = File('lib/main_debug.dart').readAsStringSync();

    expect(production, isNot(contains('main_debug')));
    expect(production, isNot(contains('PatientMicDemo')));
    expect(production, isNot(contains('debug/')));
    expect(debug, contains('PatientMicDemo'));
    expect(debug, contains("debug/patient_mic_demo.dart"));
  });
}
