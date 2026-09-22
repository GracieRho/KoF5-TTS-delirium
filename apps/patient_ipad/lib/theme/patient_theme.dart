import 'package:flutter/material.dart';

abstract final class PatientColors {
  static const ink = Color(0xFF202723);
  static const muted = Color(0xFF68716C);
  static const green = Color(0xFF2F6651);
  static const greenSoft = Color(0xFFE8F0EB);
  static const warm = Color(0xFFF4F2ED);
  static const paper = Color(0xFFFCFCF9);
  static const line = Color(0xFFD8DCD7);
  static const sunSoft = Color(0x66F4EEDC);
  static const sunGlow = Color(0x80F8E9C9);
  static const horizonBack = Color(0x80E9EEEC);
  static const horizonMiddle = Color(0x99E1E8E4);
  static const horizonFront = Color(0xA6D9E2DD);
}

ThemeData patientTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Pretendard',
  scaffoldBackgroundColor: PatientColors.warm,
  colorScheme: ColorScheme.fromSeed(
    seedColor: PatientColors.green,
    surface: PatientColors.paper,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 86,
      height: 1,
      fontWeight: FontWeight.w400,
      letterSpacing: -1.5,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    headlineLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 28,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
    ),
    titleLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 22,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: PatientColors.muted,
      fontSize: 18,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
  ),
);
