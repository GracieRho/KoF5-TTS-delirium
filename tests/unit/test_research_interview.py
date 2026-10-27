"""Synthetic preference inference contracts; no participants, providers, or network."""
from __future__ import annotations

from copy import deepcopy
import math
from pathlib import Path
import random
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'src'))
from kof5_tts.research.interview import (
    expected_information_gain, initial_posterior, interview_state,
    load_question_bank, option_likelihoods, question_probabilities, update_posterior,
)


class ResearchInterviewTests(unittest.TestCase):
    def setUp(self):
        self.bank = load_question_bank()

    def answer_next(self, answers, strategy='adaptive', seed=0, budget=5, option_id='a'):
        state = interview_state(answers, strategy, seed, budget, self.bank)
        return answers + [{'question_id': state['next_question']['id'], 'option_id': option_id}]

    def test_balanced_prior_and_public_question_hide_model_fields(self):
        state = interview_state([], question_bank=self.bank)
        self.assertAlmostEqual(state['entropy_bits'], 3)
        self.assertAlmostEqual(state['uncertainty'], 1)
        self.assertEqual(set(state['next_question']), {'id', 'scenario', 'options'})
        for option in state['next_question']['options']:
            self.assertEqual(set(option), {'id', 'text'})
        self.assertEqual(len(state['heldout_predictions']), 4)
        self.assertTrue(all(abs(sum(p['probabilities'].values()) - 1) < 1e-12
                            for p in state['heldout_predictions']))

    def test_discriminating_response_updates_only_observed_dimension(self):
        prior = initial_posterior(self.bank)
        question = next(q for q in self.bank['questions'] if q['id'] == 'nickname')
        posterior = update_posterior(self.bank, prior, question, 'b')
        familiar = sum(posterior[h['id']] for h in self.bank['hypotheses'] if h['style']['address'] == 'familiar')
        expected = .9 / (1 + math.exp(-4.4)) + .05
        self.assertAlmostEqual(familiar, expected)
        for key, value in [('ending', 'polite'), ('support', 'acknowledge')]:
            marginal = sum(posterior[h['id']] for h in self.bank['hypotheses'] if h['style'][key] == value)
            self.assertAlmostEqual(marginal, .5)
        self.assertAlmostEqual(sum(posterior.values()), 1)

    def test_expected_information_gain_has_known_symmetric_binary_value(self):
        bank = deepcopy(self.bank)
        bank['hypotheses'] = [h for h in bank['hypotheses'] if h['style']['ending'] == 'polite'
                              and h['style']['support'] == 'acknowledge']
        prior = initial_posterior(bank)
        question = next(q for q in bank['questions'] if q['id'] == 'nickname')
        p = .9 / (1 + math.exp(-4.4)) + .05
        expected = 1 + p * math.log2(p) + (1-p) * math.log2(1-p)
        self.assertAlmostEqual(expected_information_gain(bank, prior, question), expected)
        unrelated = next(q for q in bank['questions'] if q['id'] == 'waiting')
        self.assertAlmostEqual(expected_information_gain(bank, prior, unrelated), 0)

    def test_adaptive_uses_more_informative_question_before_fixed_order(self):
        adaptive = interview_state([], 'adaptive', question_bank=self.bank)
        fixed = interview_state([], 'fixed', question_bank=self.bank)
        self.assertEqual(adaptive['next_question']['id'], 'nickname')
        self.assertEqual(fixed['next_question']['id'], 'greeting')
        answers = self.answer_next([])
        after = interview_state(answers, question_bank=self.bank)
        self.assertLess(after['uncertainty'], adaptive['uncertainty'])
        self.assertNotEqual(after['next_question']['id'], answers[0]['question_id'])

    def test_replay_determinism_all_budgets_and_no_heldout_selection(self):
        elicitation = {q['id'] for q in self.bank['questions'] if q['split'] == 'elicitation'}
        for strategy in ['fixed', 'random', 'adaptive']:
            answers = []
            for i in range(8):
                state = interview_state(answers, strategy, 42, 8, self.bank)
                self.assertEqual(state, interview_state(answers, strategy, 42, 8, self.bank))
                self.assertIn(state['next_question']['id'], elicitation)
                shorter = interview_state(answers, strategy, 42, i+1, self.bank)
                self.assertEqual(state['next_question'], shorter['next_question'])
                answers = self.answer_next(answers, strategy, 42, 8, 'a' if i % 2 else 'b')
            state = interview_state(answers, strategy, 42, 8, self.bank)
            self.assertTrue(state['done'])
            self.assertIsNone(state['next_question'])
            self.assertEqual(len({a['question_id'] for a in answers}), 8)
            self.assertTrue(all(math.isfinite(p) and 0 < p < 1 for p in state['posterior'].values()))

    def test_random_selection_uses_local_rng(self):
        before = random.getstate()
        states = [interview_state([], 'random', seed, question_bank=self.bank) for seed in range(4)]
        self.assertEqual(before, random.getstate())
        self.assertGreater(len({state['next_question']['id'] for state in states}), 1)

    def test_heldout_diagnostic_assumptions_do_not_change_interview_selection(self):
        changed = deepcopy(self.bank)
        for q in changed['questions']:
            if q['split'] == 'heldout':
                q['signal'] = 5
                q['options'][0]['style'] = {'ending': 'casual'}
        answers = self.answer_next([])
        original = interview_state(answers, question_bank=self.bank)
        modified = interview_state(answers, question_bank=changed)
        self.assertEqual(original['posterior'], modified['posterior'])
        self.assertEqual(original['next_question'], modified['next_question'])

    def test_forged_heldout_duplicate_or_unknown_response_rejected(self):
        valid = self.answer_next([])
        bad = [
            [{'question_id': 'heldout_photo', 'option_id': 'a'}],
            [{'question_id': 'greeting', 'option_id': 'a'}],
            [{'question_id': valid[0]['question_id'], 'option_id': 'secret'}],
            [{'question_id': valid[0]['question_id'], 'option_id': 'a', 'target': 'hidden'}],
            valid * 2,
        ]
        for answers in bad:
            with self.subTest(answers=answers), self.assertRaises(ValueError):
                interview_state(answers, question_bank=self.bank)

    def test_explicit_zero_budget_prior_and_invalid_arguments(self):
        self.assertTrue(interview_state([], budget=0, question_bank=self.bank)['done'])
        for kwargs in [{'budget': -1}, {'budget': 9}, {'budget': True}, {'budget': 1.5},
                       {'strategy': 'oracle'}, {'seed': True}, {'seed': 2**31}, {'seed': .2}]:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                interview_state([], question_bank=self.bank, **kwargs)
        with self.assertRaises(ValueError):
            interview_state(self.answer_next([]), budget=0, question_bank=self.bank)

    def test_malformed_question_banks_are_rejected(self):
        mutations = [
            lambda b: b['questions'][1].update(id=b['questions'][0]['id']),
            lambda b: b['questions'][0].update(signal=float('nan')),
            lambda b: b['questions'][0]['options'][1].update(id='a'),
            lambda b: b['questions'][0]['options'][0].update(style={'address': 'real-parent'}),
            lambda b: b['hypotheses'][0].update(prior=True),
            lambda b: b['model'].update(lapse=0),
            lambda b: b.update(questions=[q for q in b['questions'] if q['split'] != 'heldout']),
        ]
        for mutate in mutations:
            bank = deepcopy(self.bank)
            mutate(bank)
            with self.assertRaises(ValueError):
                interview_state([], question_bank=bank)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bank.json'
            path.write_text('{"version":"unsupported"}')
            with self.assertRaises(ValueError):
                load_question_bank(path)

    def test_helpers_return_normalized_nonzero_choice_probabilities(self):
        prior = initial_posterior(self.bank)
        for question in self.bank['questions']:
            marginal = question_probabilities(self.bank, prior, question)
            self.assertAlmostEqual(sum(marginal.values()), 1)
            for hypothesis in self.bank['hypotheses']:
                probabilities = option_likelihoods(self.bank, hypothesis, question)
                self.assertAlmostEqual(sum(probabilities.values()), 1)
                self.assertTrue(all(0 < value < 1 for value in probabilities.values()))


if __name__ == '__main__':
    unittest.main()
