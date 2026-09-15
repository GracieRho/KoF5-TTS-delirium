import 'synthetic_activation.dart';

/// Scripted self-voice internal test only; this is not patient speaker evidence.
class SyntheticRiskCandidate {
  const SyntheticRiskCandidate(
    this.transcript,
    this.matchedPhrase,
    this.category,
  );

  final String transcript;
  final String matchedPhrase;
  final String category;

  static const phrases = [
    '숨을 못 쉬',
    '숨이 너무 차',
    '숨이 안 쉬',
    '가슴이 아파',
    '통증이 있어',
    '통증이 심',
    '넘어졌',
    '낙상했',
    '너무 어지러워',
    '살려줘',
  ];

  static SyntheticRiskCandidate? fromDirectedOwnVoice(String transcript) {
    final text = transcript.trim();
    if (text.isEmpty ||
        text.length > 200 ||
        SyntheticActivation.isDissent(text) ||
        !text.contains('수민아')) {
      return null; // Unknown/ambient speaker stays off the alert path.
    }
    final phrase = matchPhrase(text);
    if (phrase == null) return null;
    final category = switch (phrase) {
      '숨을 못 쉬' || '숨이 너무 차' || '숨이 안 쉬' => 'breathing',
      '가슴이 아파' => 'chest_pain',
      '넘어졌' || '낙상했' => 'fall',
      '통증이 있어' || '통증이 심' => 'pain',
      '너무 어지러워' => 'dizziness',
      _ => 'distress',
    };
    return SyntheticRiskCandidate(text, phrase, category);
  }

  static String? matchPhrase(String transcript) {
    for (final phrase in phrases) {
      if (transcript.contains(phrase)) return phrase;
    }
    return null;
  }
}
