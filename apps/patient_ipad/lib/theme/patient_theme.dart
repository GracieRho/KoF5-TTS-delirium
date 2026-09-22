import 'package:flutter/material.dart';

abstract final class PatientColors {
  static const ink = Color(0xFF243631);
  static const muted = Color(0xFF60716C);
  static const green = Color(0xFF356B5D);
  static const greenSoft = Color(0xFFE2F0EA);
  static const cream = Color(0xFFF7F4ED);
  static const line = Color(0xFFDCE4E0);
}

ThemeData patientTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: PatientColors.cream,
  colorScheme: ColorScheme.fromSeed(
    seedColor: PatientColors.green,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 76,
      height: 1,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    headlineLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 30,
      height: 1.2,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: TextStyle(
      color: PatientColors.ink,
      fontSize: 23,
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: TextStyle(
      color: PatientColors.muted,
      fontSize: 19,
      height: 1.45,
    ),
  ),
);
