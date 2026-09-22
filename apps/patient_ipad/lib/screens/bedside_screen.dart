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
          final clockAndStatus = Column(
            children: [
              ValueListenableBuilder(
                valueListenable: clock,
                builder: (context, now, _) => CurrentTimeCard(now: now),
              ),
              const SizedBox(height: 18),
              StatusCard(status: data.status),
            ],
          );
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 44 : 20,
              vertical: wide ? 34 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ContextHeader(contextData: data.context),
                    const SizedBox(height: 28),
                    if (data.message case final message?) ...[
                      SurfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wb_sunny_outlined,
                              color: PatientColors.green,
                              size: 30,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                message,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: clockAndStatus),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 6,
                            child: SchedulePanel(items: data.schedule),
                          ),
                        ],
                      )
                    else ...[
                      clockAndStatus,
                      const SizedBox(height: 18),
                      SchedulePanel(items: data.schedule),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
