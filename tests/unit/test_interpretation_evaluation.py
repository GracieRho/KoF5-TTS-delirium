"""실제 호출 없이 평가 분모·입력·호출 경계를 검사한다."""
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest
from unittest.mock import patch

import httpx

from kof5_tts.research.interpretation_evaluation import evaluate, load_cases, summarize
from kof5_tts.research.interview import interview_state
from kof5_tts.research.openrouter import FREE_MODEL

CASES = Path(__file__).resolve().parents[2] / 'configs/research/written-answer-evaluation.json'


class InterpretationEvaluationTests(unittest.TestCase):
    def test_fatal_third_attempt_or_unknown_fatality_stops_batch_and_logs_out(self):
        for fatal in (True, None, False):
            calls = []
            def respond(request):
                calls.append(request.url.path)
                if request.url.path == '/portal/config':
                    return httpx.Response(200, json={'url': 'http://127.0.0.1:54341', 'publishable_key': 'test-public'})
                if request.url.path == '/auth/v1/token':
                    return httpx.Response(200, json={'access_token': 'synthetic-session'})
                if request.url.path == '/local-studio/state':
                    return httpx.Response(200, json={'profile': {'speech_style': 'polite'}, 'memories': [{}]})
                if request.url.path == '/research-api/interview':
                    body = json.loads(request.content)
                    return httpx.Response(200, json=interview_state(body['answers'], body['strategy'], 0, body['budget']))
                if request.url.path == '/research-api/interpret':
                    detail = {'message': 'safe failure', 'attempts': [{'status': 'failed'}] * 3}
                    if fatal is not None:
                        detail['fatal'] = fatal
                    return httpx.Response(503, json={'detail': detail})
                if request.url.path == '/auth/v1/logout':
                    return httpx.Response(204)
                self.fail('Unexpected HTTP path')
            with self.subTest(fatal=fatal), TemporaryDirectory() as directory, \
                 patch('kof5_tts.research.interpretation_evaluation.httpx.Client',
                       return_value=httpx.Client(transport=httpx.MockTransport(respond))):
                output = Path(directory) / 'run'
                if fatal is False:
                    report = evaluate('http://127.0.0.1:8767', 'test', 'secret', CASES, output, FREE_MODEL, True, progress=lambda _: None)
                    self.assertEqual(report['summary']['errors'], 24)
                    self.assertIsNone(report['summary']['accuracy_completed'])
                    self.assertEqual(calls.count('/research-api/interpret'), 24)
                else:
                    with self.assertRaisesRegex(ValueError, '중단'):
                        evaluate('http://127.0.0.1:8767', 'test', 'secret', CASES, output, FREE_MODEL, True, progress=lambda _: None)
                    self.assertEqual(calls.count('/research-api/interpret'), 1)
                    self.assertFalse((output / 'summary.json').exists())
                self.assertEqual(calls[-1], '/auth/v1/logout')

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
