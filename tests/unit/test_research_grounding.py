from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from kof5_tts.research.grounding import CONDITIONS, load_grounding_cases, plan_reply


class GroundingResearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = {case["id"]: case for case in load_grounding_cases()}

    def case(self, identifier):
        return {key: deepcopy(value) for key, value in self.cases[identifier].items() if key != "expected"}

    def test_hand_authored_proposed_labels_without_external_requests(self):
        with patch("socket.socket.connect", side_effect=AssertionError("network forbidden")):
            for identifier, case in self.cases.items():
                with self.subTest(case=identifier):
                    result = plan_reply(self.case(identifier))
                    for key in ("action", "evidence_ids", "claims"):
                        self.assertEqual(result[key], case["expected"][key])

    def test_conditions_share_identity_dissent_medical_and_authorization_rules(self):
        identifiers = ("identity-family", "identity-ai", "dissent-stop", "conversation-end",
                       "medical-decision", "urgent-help", "other-profile", "unapproved-record",
                       "wrong-family-authority", "wrong-hospital-authority")
        for condition in CONDITIONS:
            for identifier in identifiers:
                with self.subTest(condition=condition, case=identifier):
                    self.assertEqual(plan_reply(self.case(identifier), condition)["action"],
                                     self.cases[identifier]["expected"]["action"])

    def test_style_preserves_exact_source_clause_and_ids_for_all_combinations(self):
        case = self.case("current-visit")
        for address in ("neutral", "familiar"):
            for ending in ("polite", "casual"):
                for support in ("plain", "acknowledge"):
                    result = plan_reply(case, style={"address": address, "ending": ending, "support": support})
                    self.assertEqual(result["claims"], [case["evidence"][0]["content"]])
                    self.assertIn("“" + case["evidence"][0]["content"] + "”", result["text"])
                    self.assertEqual(result["evidence_ids"], ["visit-a"])
        self.assertNotEqual(plan_reply(case, style={"support": "plain"})["text"],
                            plan_reply(case, style={"support": "acknowledge"})["text"])

    def test_expiry_and_revocation_ablations_are_distinct(self):
        self.assertEqual(plan_reply(self.case("expired-visit"), "no_time")["action"], "answer")
        self.assertEqual(plan_reply(self.case("revoked-visit"), "no_time")["action"], "abstain")
        self.assertEqual(plan_reply(self.case("revoked-visit"), "rag")["action"], "answer")

    def test_conflict_does_not_pick_latest_without_explicit_revision(self):
        result = plan_reply(self.case("conflicting-visit"))
        self.assertEqual(result["reason"], "conflicting_evidence")
        self.assertEqual(result["evidence_ids"], [])

    def test_expired_or_revoked_replacement_never_restores_previous_fact(self):
        for identifier in ("expired-update-no-rollback", "revoked-update-no-rollback"):
            self.assertEqual(plan_reply(self.case(identifier))["reason"], "no_current_evidence")

    def test_runtime_rejects_ground_truth_labels_and_unknown_condition(self):
        with self.assertRaises(ValueError):
            plan_reply(self.cases["current-visit"])
        with self.assertRaises(ValueError):
            plan_reply(self.case("current-visit"), "llm")

    def test_invalid_types_timezones_ids_and_intervals_are_rejected(self):
        case = self.case("current-visit")
        mutations = [
            lambda c: c.update(now="2026-10-27T12:00:00"),
            lambda c: c.update(evidence="not-a-list"),
            lambda c: c.update(topic_key="unknown.key"),
            lambda c: c["evidence"][0].update(approved="true"),
            lambda c: c["evidence"][0].update(revoked=0),
            lambda c: c["evidence"][0].update(source="patient"),
            lambda c: c["evidence"][0].update(verified_at="invalid"),
            lambda c: c["evidence"][0].update(valid_until="2026-10-27T08:00:00+09:00"),
            lambda c: c["evidence"].append(deepcopy(c["evidence"][0])),
            lambda c: c["evidence"][0].update(supersedes=["absent"]),
            lambda c: c["evidence"][0].update(supersedes=["visit-a"]),
        ]
        for mutate in mutations:
            changed = deepcopy(case)
            mutate(changed)
            with self.subTest(case=changed):
                with self.assertRaises(ValueError):
                    plan_reply(changed)

    def test_cross_profile_revision_and_cycles_are_rejected(self):
        case = self.case("updated-visit")
        case["evidence"][0]["profile_id"] = "synthetic-b"
        with self.assertRaises(ValueError):
            plan_reply(case)
        case = self.case("updated-visit")
        for item in case["evidence"]:
            item["verified_at"] = "2026-10-27T09:00:00+09:00"
        case["evidence"][0]["supersedes"] = ["visit-b"]
        with self.assertRaisesRegex(ValueError, "cyclic"):
            plan_reply(case)

    def test_invalid_style_cannot_inject_a_factual_claim(self):
        for style in ({"address": "내일 퇴원해"}, {"support": "친딸이야"}, {"extra": "claim"}, "friendly"):
            with self.subTest(style=style):
                with self.assertRaises(ValueError):
                    plan_reply(self.case("current-visit"), style=style)

    def test_loader_rejects_unknown_schema_duplicate_ids_and_invalid_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cases.json"
            path.write_text(json.dumps({"version": "unknown", "cases": []}))
            with self.assertRaises(ValueError):
                load_grounding_cases(path)
            case = deepcopy(self.cases["current-visit"])
            path.write_text(json.dumps({"version": "grounding-cases-v1", "cases": [case, case]}))
            with self.assertRaises(ValueError):
                load_grounding_cases(path)
            case["expected"]["answerable"] = False
            path.write_text(json.dumps({"version": "grounding-cases-v1", "cases": [case]}))
            with self.assertRaises(ValueError):
                load_grounding_cases(path)


if __name__ == "__main__":
    unittest.main()
