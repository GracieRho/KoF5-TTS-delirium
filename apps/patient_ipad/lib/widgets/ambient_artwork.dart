import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => const IgnorePointer(
    child: SizedBox(
      key: ValueKey('guidance-landscape-artwork'),
      width: 360,
      height: 132,
      child: CustomPaint(painter: _GuidanceLandscapePainter()),
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

class _GuidanceLandscapePainter extends CustomPainter {
  const _GuidanceLandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.34),
      size.height * 0.28,
      Paint()..color = PatientColors.sunGlow,
    );
    _drawHorizon(
      canvas,
      size,
      baseline: 0.66,
      crest: 0.44,
      color: PatientColors.horizonBack,
    );
    _drawHorizon(
      canvas,
      size,
      baseline: 0.82,
      crest: 0.60,
      color: PatientColors.horizonMiddle,
    );
    _drawHorizon(
      canvas,
      size,
      baseline: 0.96,
      crest: 0.72,
      color: PatientColors.horizonFront,
    );
  }

  void _drawHorizon(
    Canvas canvas,
    Size size, {
    required double baseline,
    required double crest,
    required Color color,
  }) {
    final path = Path()
      ..moveTo(0, size.height * baseline)
      ..cubicTo(
        size.width * 0.22,
        size.height * crest,
        size.width * 0.38,
        size.height * crest,
        size.width * 0.56,
        size.height * baseline,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * (baseline + 0.11),
        size.width * 0.84,
        size.height * (crest - 0.03),
        size.width,
        size.height * crest,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
