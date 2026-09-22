import 'package:flutter/material.dart';

import '../models/bedside_status.dart';
import '../theme/patient_theme.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({required this.status, super.key});

  final BedsideStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.only(left: 20),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: PatientColors.green, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            status.description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    ),
  );
}
