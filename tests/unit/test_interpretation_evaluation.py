"""실제 호출 없이 평가 분모·입력·호출 경계를 검사한다."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from kof5_tts.research.interpretation_evaluation import evaluate, load_cases, summarize
from kof5_tts.research.openrouter import FREE_MODEL

CASES = Path(__file__).resolve().parents[2] / 'configs/research/written-answer-evaluation.json'


class InterpretationEvaluationTests(unittest.TestCase):
    def test_synthetic_cases_have_explicit_labels_and_balanced_options(self):
        cases = load_cases(CASES)['cases']
        self.assertEqual(len(cases), 24)
        self.assertEqual(sum(c['expected_option_id'] is None for c in cases), 4)
        for question in {c['question_id'] for c in cases}:
            self.assertEqual({c['expected_option_id'] for c in cases if c['question_id'] == question and c['kind'] == 'paraphrase'}, {'a', 'b', 'c', 'd'})

    def test_errors_are_separate_from_null_and_stay_in_all_request_denominator(self):
        rows = [{'status': 'success', 'expected_option_id': None, 'predicted_option_id': None, 'cost': 0, 'attempts': [{}]},
                {'status': 'success', 'expected_option_id': 'a', 'predicted_option_id': 'b', 'cost': 0, 'attempts': [{}]},
                {'status': 'error', 'expected_option_id': 'a', 'attempts': [{}, {}, {}]}]
        report = summarize(rows)
        self.assertEqual(report['accuracy_completed'], .5)
        self.assertEqual(report['correct_over_all_requests'], 1 / 3)
        self.assertEqual(report['errors'], 1)
        self.assertEqual(report['model_attempts'], 5)
        self.assertIsNone(summarize([])['accuracy_completed'])

    def test_unsafe_target_paid_model_and_missing_consent_never_start_client(self):
        with TemporaryDirectory() as directory, patch('kof5_tts.research.interpretation_evaluation.httpx.Client') as client:
            for target, model, consent in [('https://example.org', FREE_MODEL, True),
                                           ('http://127.0.0.1:8767', 'paid/model', True),
                                           ('http://127.0.0.1:8767', FREE_MODEL, False)]:
                with self.assertRaises(ValueError):
                    evaluate(target, 'test', 'secret', CASES, Path(directory) / 'run', model, consent)
            client.assert_not_called()
