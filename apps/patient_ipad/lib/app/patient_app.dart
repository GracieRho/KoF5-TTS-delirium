import 'package:flutter/material.dart';

import '../controllers/bedside_clock.dart';
import '../controllers/patient_runtime_controller.dart';
import '../models/bedside_data.dart';
import '../screens/bedside_screen.dart';
import '../theme/patient_theme.dart';

class PatientApp extends StatefulWidget {
  const PatientApp({
    this.data = BedsideData.unverified,
    this.now,
    this.runtime,
    this.startRuntime = true,
    super.key,
  });

  final BedsideData data;
  final DateTime Function()? now;
  final PatientRuntimeController? runtime;
  final bool startRuntime;

  @override
  State<PatientApp> createState() => _PatientAppState();
}

class _PatientAppState extends State<PatientApp> {
  late final BedsideClock _clock = BedsideClock(now: widget.now);
  late final PatientRuntimeController _runtime =
      widget.runtime ?? PatientRuntimeController();

  @override
  void initState() {
    super.initState();
    if (widget.startRuntime) _runtime.start();
  }

  @override
  void dispose() {
    _clock.dispose();
    if (widget.runtime == null) _runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _runtime,
    builder: (context, runtime, _) => MaterialApp(
      title: '병실 안내',
      debugShowCheckedModeBanner: false,
      theme: patientTheme(),
      home: BedsideScreen(
        data: widget.data.withRuntime(
          status: runtime.status,
          message: runtime.message,
        ),
        clock: _clock,
      ),
    ),
  );
}
