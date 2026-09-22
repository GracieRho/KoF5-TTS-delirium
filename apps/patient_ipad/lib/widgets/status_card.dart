import 'package:flutter/material.dart';

import '../models/bedside_status.dart';
import '../theme/patient_theme.dart';
import 'surface_card.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({required this.status, super.key});

  final BedsideStatus status;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: PatientColors.greenSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              status == BedsideStatus.playing
                  ? Icons.volume_up_rounded
                  : status == BedsideStatus.waiting
                  ? Icons.notifications_none_rounded
                  : Icons.bedtime_outlined,
              color: PatientColors.green,
              size: 34,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  status.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
