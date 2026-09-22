import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/patient_theme.dart';

class TimeAmbientArtwork extends StatelessWidget {
  const TimeAmbientArtwork({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: SizedBox(
      key: ValueKey('time-ambient-artwork'),
      width: 164,
      height: 164,
      child: CustomPaint(painter: _TimeAmbientPainter()),
    ),
  );
}

class GuidanceLandscapeArtwork extends StatelessWidget {
  const GuidanceLandscapeArtwork({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox.expand(
      key: const ValueKey('guidance-landscape-artwork'),
      child: SvgPicture.asset(
        'assets/images/guidance_landscape.svg',
        fit: BoxFit.cover,
        alignment: Alignment.centerRight,
      ),
    ),
  );
}

class _TimeAmbientPainter extends CustomPainter {
  const _TimeAmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width, 0),
      size.width,
      Paint()..color = PatientColors.sunSoft,
    );
    canvas.drawCircle(
      Offset(size.width, 0),
      size.width * 0.62,
      Paint()..color = PatientColors.sunGlow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
