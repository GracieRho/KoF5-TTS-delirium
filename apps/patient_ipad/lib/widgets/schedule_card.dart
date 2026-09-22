import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import '../theme/patient_theme.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({required this.item, super.key});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: item.isCurrent ? PatientColors.greenSoft : Colors.transparent,
      border: item.isCurrent
          ? const Border(left: BorderSide(color: PatientColors.green, width: 2))
          : null,
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(item.isCurrent ? 18 : 0, 20, 0, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              item.timeLabel,
              style: const TextStyle(
                color: PatientColors.green,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: PatientColors.ink,
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.description case final description?) ...[
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      color: PatientColors.muted,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
