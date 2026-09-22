import 'package:flutter/material.dart';

import '../theme/patient_theme.dart';
import 'surface_card.dart';

class CurrentTimeCard extends StatelessWidget {
  const CurrentTimeCard({required this.now, super.key});

  final DateTime now;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour < 12 ? '오전' : '오후';
    final minute = now.minute.toString().padLeft(2, '0');
    return SurfaceCard(
      child: Semantics(
        label: '$period $hour시 $minute분, ${now.month}월 ${now.day}일',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}요일',
              style: const TextStyle(
                color: PatientColors.green,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$period $hour:$minute',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
