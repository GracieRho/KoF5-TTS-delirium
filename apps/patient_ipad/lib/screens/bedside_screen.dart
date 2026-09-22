import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/bedside_clock.dart';
import '../models/bedside_data.dart';
import '../widgets/ambient_artwork.dart';
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
          final horizontal = wide ? 28.0 : 16.0;
          final vertical = wide ? 24.0 : 16.0;
          final minimumHeight = math.max(
            0.0,
            constraints.maxHeight - vertical * 2,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontal,
              vertical: vertical,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: wide
                    ? _WideLayout(
                        data: data,
                        clock: clock,
                        minimumHeight: minimumHeight,
                      )
                    : _StackedLayout(data: data, clock: clock),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.data,
    required this.clock,
    required this.minimumHeight,
  });

  final BedsideData data;
  final BedsideClock clock;
  final double minimumHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(minimumHeight, 660.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(32),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned(
                              top: -32,
                              right: -32,
                              child: TimeAmbientArtwork(),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ValueListenableBuilder(
                                valueListenable: clock,
                                builder: (context, now, _) =>
                                    CurrentTimeCard(now: now),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      flex: 2,
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(32),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ContextHeader(contextData: data.context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 11,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(32),
                  child: SchedulePanel(items: data.schedule),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 154,
          child: SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  left: 300,
                  right: -36,
                  bottom: -24,
                  height: 154,
                  child: GuidanceLandscapeArtwork(),
                ),
                FractionallySizedBox(
                  widthFactor: 0.62,
                  heightFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: StatusCard(status: data.status),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
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
      SurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(top: -24, right: -24, child: TimeAmbientArtwork()),
            ValueListenableBuilder(
              valueListenable: clock,
              builder: (context, now, _) => CurrentTimeCard(now: now),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.all(24),
        child: ContextHeader(contextData: data.context),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.all(24),
        child: SchedulePanel(items: data.schedule),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 142),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: 190,
                right: -24,
                bottom: -24,
                height: 166,
                child: GuidanceLandscapeArtwork(),
              ),
              FractionallySizedBox(
                widthFactor: 0.78,
                child: StatusCard(status: data.status),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
