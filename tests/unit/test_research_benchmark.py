import copy
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.research.benchmark import (
    CONDITIONS, export_inputs, grounding_summary, load_responses, paired_difference_ci, percentile, run_benchmark,
    score_grounding, score_responses, simulate_answers, write_report,
)
from kof5_tts.research.interview import load_question_bank


def unknown_case():
    return {
        "id": "unknown-flower", "profile_id": "synthetic-a", "category": "missing",
        "question": "좋아하는 꽃이 무엇인가요?", "topic_key": "family.flower",
        "now": "2026-10-27T09:00:00+09:00", "evidence": [],
        "expected": {"action": "abstain", "claims": [], "evidence_ids": [], "answerable": False},
    }


class ResearchBenchmarkTests(unittest.TestCase):
    def test_percentiles_and_paired_groups_are_reproducible(self):
        self.assertIsNone(percentile([], 0.5))
        self.assertEqual(percentile([30, 10, 20], 0.5), 20)
        self.assertEqual(percentile([0, 100], 0.95), 95)
        result = paired_difference_ci({"a": 1, "b": 0.5}, {"a": 0, "b": 0.5}, seed=9, samples=100)
        self.assertEqual(result["difference"], 0.5)
        self.assertEqual(result["group_count"], 2)
        self.assertEqual(result, paired_difference_ci({"b": 0.5, "a": 1}, {"b": 0.5, "a": 0}, seed=9, samples=100))
        with self.assertRaises(ValueError):
            paired_difference_ci({"a": 1}, {"b": 1})

    def test_manual_ground_truth_detects_wrong_claim_and_does_not_reward_abstention(self):
        case = unknown_case()
        case["expected"] = {"action": "answer", "claims": ["방문은 오후 4시입니다."], "evidence_ids": ["current"]}
        wrong = score_grounding(case, {"action": "answer", "claims": ["방문은 오후 3시입니다."], "evidence_ids": ["old"]})
        self.assertEqual(wrong["unsupported_claim_count"], 1)
        self.assertTrue(wrong["erroneous_answer"])
        absent = score_grounding(case, {"action": "abstain", "claims": [], "evidence_ids": []})
        summary = grounding_summary([{**absent, "latency_ms": 2}])
        self.assertEqual(summary["coverage"], 0)
        self.assertEqual(summary["valid_answer_rate"], 0)
        self.assertIsNone(summary["selective_risk"])
        self.assertIsNone(summary["unsupported_claim_rate"])

    def test_hidden_answers_are_frozen_for_all_questions_and_do_not_mutate_bank(self):
        bank = load_question_bank()
        original = copy.deepcopy(bank)
        target = simulate_answers(bank, bank["hypotheses"][0], seed=9, respondent_model="context_dependent")
        self.assertEqual(set(target), {question["id"] for question in bank["questions"]})
        self.assertEqual(target, simulate_answers(bank, bank["hypotheses"][0], seed=9, respondent_model="context_dependent"))
        self.assertEqual(bank, original)

    def test_offline_benchmark_groups_repeated_seeds_by_profile_and_reproduces_scores(self):
        def run():
            with patch("socket.socket.connect", side_effect=AssertionError("Network disabled")):
                return run_benchmark(grounding_cases=[unknown_case()], seed=9, seeds=2, max_budget=1, bootstrap_samples=20, latency_repeats=1)
        first = run()
        second = run()
        self.assertEqual(first["interview_comparisons"], second["interview_comparisons"])
        self.assertEqual(first["metadata"]["question_bank_sha256"], second["metadata"]["question_bank_sha256"])
        self.assertEqual(first["metadata"]["provider_requests"], 0)
        self.assertEqual(len(first["grounding_rows"]), 4)
        profiles = len(load_question_bank()["hypotheses"])
        self.assertEqual(len(first["interview_rows"]), 2 * profiles * 2 * 3)
        self.assertTrue(all(row["group_count"] == profiles for row in first["interview_comparisons"]))
        for row in first["interview_summary"]:
            self.assertEqual(row["profile_count"], profiles)
            self.assertEqual(row["trial_count"], profiles * 2)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result"
            write_report(first, output)
            self.assertEqual({path.name for path in output.iterdir()}, {"results.json", "report.md", "report.html", "interview.csv", "grounding.csv"})
            self.assertIn("실제 참여자", (output / "report.html").read_text())
            self.assertEqual(json.loads((output / "results.json").read_text())["metadata"]["provider_requests"], 0)
            with (output / "interview.csv").open() as stream:
                self.assertEqual(len(list(csv.DictReader(stream))), len(first["interview_rows"]))
            with self.assertRaises(ValueError):
                write_report(first, output)

    def test_cli_runs_in_new_output_and_preserves_existing_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = root / "cases.json"
            cases.write_text(json.dumps({"version": "grounding-cases-v1", "cases": [unknown_case()]}))
            output = root / "result"
            command = [sys.executable, str(ROOT / "scripts/benchmark_research.py"), "--output", str(output), "--grounding-cases", str(cases), "--seeds", "1", "--max-budget", "1", "--bootstrap-samples", "10", "--latency-repeats", "1"]
            completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("공급자 호출 0건", completed.stdout)
            before = (output / "results.json").read_bytes()
            again = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(again.returncode, 0)
            self.assertEqual((output / "results.json").read_bytes(), before)

    def test_invalid_bounds_fail_before_work(self):
        for kwargs in [{"seeds": 0}, {"max_budget": True}, {"bootstrap_samples": 10001}, {"latency_repeats": 0}, {"seed": -1}, {"seed": 2**31}, {"seed": 2**31 - 1, "seeds": 2}]:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                run_benchmark(**kwargs)

    def test_external_annotations_require_complete_reviewed_pairs_and_finite_latency(self):
        case = unknown_case()
        records = [{
            "case_id": case["id"], "condition": condition, "action": "abstain",
            "text": '=HYPERLINK("https://example.invalid")', "claims": [], "evidence_ids": [], "claims_reviewed": True,
        } for condition in CONDITIONS]
        with patch("socket.socket.connect", side_effect=AssertionError("Network disabled")):
            report = score_responses([case], records)
        self.assertEqual(report["metadata"]["mode"], "offline_external_annotations")
        self.assertEqual(report["interview_rows"], [])
        self.assertTrue(all(row["latency_p50_ms"] is None for row in report["grounding_summary"]))
        for invalid in [records[:-1], records + records[:1], [{**records[0], "claims_reviewed": False}, *records[1:]], [{**records[0], "elapsed_ms": float("nan")}, *records[1:]], [{**records[0], "action": []}, *records[1:]]]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                score_responses([case], invalid)
        with tempfile.TemporaryDirectory() as directory:
            write_report(report, Path(directory) / "report")
            self.assertIn("인터뷰 시뮬레이션은 실행하지 않았습니다", (Path(directory) / "report/report.html").read_text())
            with (Path(directory) / "report/grounding.csv").open() as stream:
                self.assertTrue(next(csv.DictReader(stream))["text"].startswith("'="))

    def test_exported_inputs_exclude_labels_and_external_cli_does_not_simulate(self):
        case = unknown_case()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "inputs.jsonl"
            export_inputs([case], manifest)
            inputs = [json.loads(line) for line in manifest.read_text().splitlines()]
            self.assertEqual(len(inputs), 4)
            for record in inputs:
                self.assertNotIn("expected", record["input"])
                self.assertNotIn("category", record["input"])
                self.assertNotIn("description", record["input"])
                self.assertEqual(record["input"]["id"], "case-0001")
            with self.assertRaises(FileExistsError):
                export_inputs([case], manifest)
            cases = root / "cases.json"
            cases.write_text(json.dumps({"version": "grounding-cases-v1", "cases": [case]}))
            responses = root / "responses.jsonl"
            records = [{
                "case_id": case["id"], "condition": condition, "action": "abstain", "text": "확인된 정보가 없습니다.",
                "claims": [], "evidence_ids": [], "claims_reviewed": True,
            } for condition in CONDITIONS]
            responses.write_text("\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n")
            self.assertEqual(load_responses(responses), records)
            completed = subprocess.run([
                sys.executable, str(ROOT / "scripts/benchmark_research.py"), "--output", str(root / "scored"),
                "--grounding-cases", str(cases), "--responses", str(responses),
            ], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads((root / "scored/results.json").read_text())
            self.assertEqual(report["metadata"]["mode"], "offline_external_annotations")
            self.assertEqual(report["interview_rows"], [])


if __name__ == "__main__":
    unittest.main()
