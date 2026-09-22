import 'package:flutter/material.dart';

import '../theme/patient_theme.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(28),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: PatientColors.line),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D1F332D),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}
