from __future__ import annotations

from collections import Counter
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))
from kof5_tts.research.experiment import (
    allocation, analyze_audio, analyze_critical, analyze_pairwise,
    analyze_preferences, analyze_voice, bootstrap_mean, read_csv, STRATEGIES, VOICE_CONDITIONS,
)


def preference(person="P1", strategy="fixed", scenario="H1", correct="1", count="5"):
    return {"participant_id": person, "strategy": strategy, "scenario_id": scenario,
            "correct": correct, "question_count": count, "elapsed_seconds": "30", "timing_kind": "live-interview"}


def audio(**changes):
    return {"recording_id": "R1", "clock_id": "external-recording-1", "output_route": "speaker",
            "speech_end_seconds": "1", "first_audible_seconds": "3", "playback_command_seconds": "2.5", **changes}


class ExperimentTests(unittest.TestCase):
    def test_balanced_orders_and_seed(self):
        rows = allocation(12, 4)
        self.assertEqual(rows, allocation(12, 4))
        self.assertNotEqual(rows, allocation(12, 5))
        for position in range(3):
            self.assertEqual(Counter(row["strategy_order"].split("|")[position] for row in rows), {strategy: 4 for strategy in STRATEGIES})
        for position in range(4):
            self.assertEqual(Counter(row["voice_order"].split("|")[position] for row in rows), {condition: 3 for condition in VOICE_CONDITIONS})
        transitions = Counter()
        for row in rows[:4]:
            order = row["voice_order"].split("|")
            transitions.update(zip(order, order[1:]))
        self.assertEqual(len(transitions), 12)
        self.assertEqual(set(transitions.values()), {1})
        for value in (0, -1, True, 1.2, 10001):
            with self.assertRaises(ValueError):
                allocation(value)

    def test_preferences_use_participants_not_repeated_scenarios_as_bootstrap_unit(self):
        rows = [preference("P1", strategy, f"H{i}", "1" if strategy == "adaptive" else "0") for i in range(10) for strategy in ("fixed", "adaptive")]
        rows += [preference("P2", "adaptive", "H1", "0"), preference("P2", "fixed", "H1", "1")]
        result = analyze_preferences(rows, repetitions=100)["comparisons"]["adaptive_minus_fixed"]
        self.assertEqual(result["n_participants"], 2)
        self.assertEqual(result["complete_scenario_pairs"], 11)
        self.assertEqual(result["mean"], 0)
        self.assertEqual(result["ci95"], [-1, 1])

    def test_missing_preferences_never_filled_or_counted_complete(self):
        rows = [preference(correct=""), preference(strategy="adaptive"), preference("P2", "adaptive")]
        result = analyze_preferences(rows)["comparisons"]["adaptive_minus_fixed"]
        self.assertEqual(result["missing_scenario_pairs"], 2)
        self.assertEqual(result["n_participants"], 0)
        self.assertIsNone(result["mean"])
        self.assertIsNone(result["ci95"])

    def test_duplicate_wrong_budget_or_invalid_preferences_rejected(self):
        for rows in (
            [preference(), preference()],
            [preference(), preference(strategy="adaptive", count="4")],
            [preference(correct="2")],
            [preference(count="nan")],
            [preference(count="1.5")],
            [preference(), {**preference(strategy="adaptive"), "timing_kind": "replay-answer-sum"}],
        ):
            with self.assertRaises(ValueError):
                analyze_preferences(rows)

    def test_bootstrap_is_deterministic_and_single_person_has_no_population_interval(self):
        self.assertEqual(bootstrap_mean([.2, .5, 1], seed=4, repetitions=100), bootstrap_mean([.2, .5, 1], seed=4, repetitions=100))
        self.assertIsNone(bootstrap_mean([1])["ci95"])
        with self.assertRaises(ValueError):
            bootstrap_mean([float("nan")])
        with self.assertRaises(ValueError):
            bootstrap_mean([1], repetitions=0)

    def test_blind_pairwise_orientation_ties_missing_and_other_pairs(self):
        key = [{"candidate_id": "A", "condition": "fixed"}, {"candidate_id": "B", "condition": "adaptive"}, {"candidate_id": "C", "condition": "random"}]
        rows = [
            {"participant_id": "P1", "scenario_id": "H1", "left_id": "A", "right_id": "B", "choice": "right"},
            {"participant_id": "P1", "scenario_id": "H2", "left_id": "B", "right_id": "A", "choice": "tie"},
            {"participant_id": "P2", "scenario_id": "H1", "left_id": "B", "right_id": "A", "choice": "right"},
            {"participant_id": "P2", "scenario_id": "H2", "left_id": "A", "right_id": "B", "choice": ""},
            {"participant_id": "P2", "scenario_id": "H2", "left_id": "A", "right_id": "C", "choice": "left"},
        ]
        result = analyze_pairwise(rows, key, repetitions=100)
        self.assertEqual(result["completed_pairs"], 3)
        self.assertEqual(result["missing_pairs"], 1)
        self.assertEqual(result["other_condition_pairs"], 1)
        self.assertEqual(result["mean"], .375)
        with self.assertRaises(ValueError):
            analyze_pairwise(rows + [rows[0]], key)
        with self.assertRaises(ValueError):
            analyze_pairwise(rows, key[:2])

    def test_audible_and_command_endpoints_are_separate(self):
        result = analyze_audio([audio(), audio(recording_id="R2", first_audible_seconds="5", playback_command_seconds="")])
        self.assertEqual(result["first_audible_latency"]["n"], 2)
        self.assertEqual(result["first_audible_latency"]["p50_seconds"], 3)
        self.assertAlmostEqual(result["first_audible_latency"]["p95_seconds"], 3.9)
        self.assertEqual(result["playback_command_latency"]["n"], 1)
        self.assertEqual(result["command_to_audible"]["p50_seconds"], .5)

    def test_invalid_or_missing_audio_markers_rejected(self):
        for changes in ({"speech_end_seconds": "-1"}, {"first_audible_seconds": "nan"},
                        {"first_audible_seconds": ""}, {"first_audible_seconds": ".5"},
                        {"playback_command_seconds": "4"}, {"clock_id": ""}, {"output_route": ""}):
            with self.assertRaises(ValueError):
                analyze_audio([audio(**changes)])
        with self.assertRaises(ValueError):
            analyze_audio([audio(), audio()])
        with self.assertRaises(ValueError):
            analyze_audio([audio(), audio(recording_id="R2", output_route="headphones")])

    def test_manual_critical_information_omission_and_normalization(self):
        rows = [{"sample_id": "S1", "category": "name", "reference": "가", "heard": "가", "assessed": "1"},
                {"sample_id": "S1", "category": "negation", "reference": "안한다", "heard": "", "assessed": "1"},
                {"sample_id": "S1", "category": "time", "reference": "3시", "heard": "", "assessed": ""}]
        result = analyze_critical(rows)
        self.assertEqual(result["categories"]["name"]["errors"], 0)
        self.assertEqual(result["categories"]["negation"]["error_rate"], 1)
        self.assertEqual(result["missing_annotations"], 1)
        self.assertEqual(result["reference_characters"], 4)
        self.assertEqual(result["annotated_span_cer"], .75)
        self.assertNotIn("안한다", json.dumps(result, ensure_ascii=False))
        with self.assertRaises(ValueError):
            analyze_critical(rows + [rows[0]])

    def test_voice_factorial_contrasts_use_complete_matched_sets(self):
        rows = [{"participant_id": person, "item_id": "I1", "condition": condition, "outcome": "content_fit", "rating": str(score)}
                for person in ("P1", "P2") for condition, score in zip(VOICE_CONDITIONS, (4, 7, 2, 3))]
        rows.append({"participant_id": "P3", "item_id": "I1", "condition": VOICE_CONDITIONS[0], "outcome": "content_fit", "rating": "7"})
        result = analyze_voice(rows, repetitions=100)["outcomes"]["content_fit"]
        self.assertEqual(result["complete_item_sets"], 2)
        self.assertEqual(result["missing_item_sets"], 1)
        self.assertEqual(result["contrasts"]["familiar_minus_unfamiliar"]["mean"], 3)
        self.assertEqual(result["contrasts"]["personalized_minus_generic"]["mean"], 2)
        self.assertEqual(result["contrasts"]["voice_by_content_interaction"]["mean"], 2)
        with self.assertRaises(ValueError):
            analyze_voice(rows + [rows[0]])
        with self.assertRaises(ValueError):
            analyze_voice([{**rows[0], "rating": "8"}])

    def test_csv_truncated_extra_columns_and_duplicate_headers_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "input.csv"
            for text in ("a,a\n1,2\n", "a,b\n1\n", "a,b\n1,2,3\n"):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    read_csv(path, ("a",))

    def test_cli_prepares_only_blank_human_templates_and_analyzes_explicit_synthetic_examples(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "study"
            cmd = [sys.executable, str(ROOT / "scripts/prepare_research_study.py"), "--output", str(output), "--participants", "2"]
            subprocess.run(cmd, check=True, capture_output=True)
            with (output / "preferences.csv").open() as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 24)
            self.assertTrue(all(row["correct"] == row["question_count"] == row["elapsed_seconds"] == "" for row in rows))
            self.assertEqual((output / "preferences.csv").stat().st_mode & 0o777, 0o600)
            for analysis, filename in (("preferences", "preferences.csv"), ("pairwise", "pairwise.csv"), ("audio", "audio_timestamps.csv"), ("voice", "voice_ratings.csv"), ("critical", "critical_information.csv")):
                report = output / f"{analysis}.json"
                command = [sys.executable, str(ROOT / "scripts/analyze_research_study.py"), analysis,
                           str(output / "synthetic-example" / filename), "--output", str(report), "--data-kind", "synthetic", "--bootstrap", "100"]
                if analysis == "pairwise":
                    command += ["--key", str(output / "synthetic-example/coordinator_blind_key.csv")]
                subprocess.run(command, check=True, capture_output=True)
                self.assertEqual(json.loads(report.read_text())["data_kind"], "synthetic")
                self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
