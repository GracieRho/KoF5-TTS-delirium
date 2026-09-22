import 'package:flutter/material.dart';

import '../controllers/bedside_clock.dart';
import '../models/bedside_data.dart';
import '../theme/patient_theme.dart';
import '../widgets/context_header.dart';
import '../widgets/current_time_card.dart';
import '../widgets/schedule_panel.dart';
import '../widgets/status_card.dart';
import '../widgets/surface_card.dart';

class BedsideScreen extends StatelessWidget {
  const BedsideScreen({required this.data, required this.clock, super.key});

  final BedsideData data;
  final BedsideClock clock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final outerHorizontal = wide ? 36.0 : 16.0;
          final outerVertical = wide ? 30.0 : 16.0;
          final workspacePadding = wide ? 44.0 : 24.0;
          final minHeight = constraints.maxHeight - outerVertical * 2;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: outerHorizontal,
              vertical: outerVertical,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 1180,
                  minHeight: minHeight > 0 ? minHeight : 0,
                ),
                child: SurfaceCard(
                  padding: EdgeInsets.all(workspacePadding),
                  child: wide
                      ? _WideLayout(data: data, clock: clock)
                      : _StackedLayout(data: data, clock: clock),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.data, required this.clock});

  final BedsideData data;
  final BedsideClock clock;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder(
                  valueListenable: clock,
                  builder: (context, now, _) => CurrentTimeCard(now: now),
                ),
                const SizedBox(height: 48),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: PatientColors.line,
                ),
                const SizedBox(height: 30),
                ContextHeader(contextData: data.context),
              ],
            ),
          ),
          const SizedBox(width: 40),
          const SizedBox(
            height: 340,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: PatientColors.line,
            ),
          ),
          const SizedBox(width: 40),
          Expanded(flex: 6, child: SchedulePanel(items: data.schedule)),
        ],
      ),
      const SizedBox(height: 42),
      const Divider(height: 1, thickness: 1, color: PatientColors.line),
      const SizedBox(height: 28),
      StatusCard(status: data.status),
    ],
  );
}

class _StackedLayout extends StatelessWidget {
  const _StackedLayout({required this.data, required this.clock});

  final BedsideData data;
  final BedsideClock clock;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ValueListenableBuilder(
        valueListenable: clock,
        builder: (context, now, _) => CurrentTimeCard(now: now),
      ),
      const SizedBox(height: 34),
      const Divider(height: 1, thickness: 1, color: PatientColors.line),
      const SizedBox(height: 26),
      ContextHeader(contextData: data.context),
      const SizedBox(height: 34),
      const Divider(height: 1, thickness: 1, color: PatientColors.line),
      const SizedBox(height: 32),
      SchedulePanel(items: data.schedule),
      const SizedBox(height: 34),
      const Divider(height: 1, thickness: 1, color: PatientColors.line),
      const SizedBox(height: 26),
      StatusCard(status: data.status),
    ],
  );
}
