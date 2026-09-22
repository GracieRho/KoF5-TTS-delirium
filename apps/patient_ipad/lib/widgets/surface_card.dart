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
      color: PatientColors.paper,
      border: Border.all(color: const Color(0xFFDDE0DC)),
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A26332C),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
        BoxShadow(
          color: Color(0x05000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Padding(padding: padding, child: child),
    ),
  );
}
