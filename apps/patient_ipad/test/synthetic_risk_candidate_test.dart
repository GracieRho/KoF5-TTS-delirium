import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_risk_candidate.dart';

void main() {
  test(
    'companion risk phrases become bounded direct-name synthetic candidates',
    () {
      const phrase = [
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
      expect(SyntheticRiskCandidate.phrases, phrase);
      for (final risk in phrase) {
        final candidate = SyntheticRiskCandidate.fromDirectedOwnVoice(
          '수민아, $risk.',
        );
        expect(candidate?.matchedPhrase, risk);
        expect(candidate?.category, isNotEmpty);
      }
    },
  );

  test(
    'ambient, dissent and oversized transcripts cannot create a candidate',
    () {
      for (final text in [
        '숨을 못 쉬겠어',
        'TV에서 수민아 하고 말했어',
        '수민아 그만해. 숨을 못 쉬겠어',
      '수민아 숨을 못 쉬${'가' * 201}',
      ]) {
        expect(SyntheticRiskCandidate.fromDirectedOwnVoice(text), isNull);
      }
    },
  );
}
