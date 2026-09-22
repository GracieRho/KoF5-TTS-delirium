import 'package:flutter/material.dart';

import '../models/bedside_context.dart';
import '../theme/patient_theme.dart';

class ContextHeader extends StatelessWidget {
  const ContextHeader({required this.contextData, super.key});

  final BedsideContext contextData;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '현재 위치',
        style: TextStyle(
          color: PatientColors.muted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        contextData.verified
            ? '${contextData.hospital}  ·  ${contextData.ward}  ·  ${contextData.room}'
            : '병원 정보를 확인하고 있습니다',
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: const TextStyle(
          color: PatientColors.ink,
          fontSize: 25,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
    ],
  );
}
