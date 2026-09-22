import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import 'schedule_card.dart';
import 'surface_card.dart';

class SchedulePanel extends StatelessWidget {
  const SchedulePanel({required this.items, super.key});

  final List<ScheduleItem> items;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘의 일정', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 22),
        if (items.isEmpty)
          const Text('오늘 예정된 일정이 없습니다.')
        else
          for (var index = 0; index < items.length; index++) ...[
            ScheduleCard(item: items[index]),
            if (index != items.length - 1) const SizedBox(height: 12),
          ],
      ],
    ),
  );
}
