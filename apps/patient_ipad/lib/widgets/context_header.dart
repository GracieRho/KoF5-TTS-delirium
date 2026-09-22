import 'package:flutter/material.dart';

import '../models/bedside_context.dart';
import '../theme/patient_theme.dart';

class ContextHeader extends StatelessWidget {
  const ContextHeader({required this.contextData, super.key});

  final BedsideContext contextData;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.local_hospital_rounded,
        color: PatientColors.green,
        size: 30,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          contextData.verified
              ? '${contextData.hospital}  ·  ${contextData.ward}  ·  ${contextData.room}'
              : '병원 정보를 확인하고 있습니다',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PatientColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
