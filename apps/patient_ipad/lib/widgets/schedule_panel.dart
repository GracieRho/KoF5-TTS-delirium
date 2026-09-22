import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import '../theme/patient_theme.dart';
import 'schedule_card.dart';

class SchedulePanel extends StatelessWidget {
  const SchedulePanel({required this.items, super.key});

  final List<ScheduleItem> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('병원 일정', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 22),
      const Divider(height: 1, thickness: 1, color: PatientColors.line),
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Text(
            '확인된 일정이 없습니다.',
            style: TextStyle(
              color: PatientColors.muted,
              fontSize: 18,
              height: 1.5,
            ),
          ),
        )
      else
        for (var index = 0; index < items.length; index++) ...[
          ScheduleCard(item: items[index]),
          if (index != items.length - 1)
            const Divider(height: 1, thickness: 1, color: PatientColors.line),
        ],
    ],
  );
}
