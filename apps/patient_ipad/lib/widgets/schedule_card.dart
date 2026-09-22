import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import '../theme/patient_theme.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({required this.item, super.key});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
    decoration: BoxDecoration(
      color: item.isCurrent ? PatientColors.greenSoft : const Color(0xFFF7F9F8),
      borderRadius: BorderRadius.circular(20),
      border: item.isCurrent
          ? Border.all(color: const Color(0xFFB8D8CC))
          : null,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            item.timeLabel,
            style: const TextStyle(
              color: PatientColors.green,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.description case final description?) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: PatientColors.muted,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
