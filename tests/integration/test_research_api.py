"""합성 연구 경로의 opt-in·출처·입력·비용 경계를 검사한다."""

import os
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch, AsyncMock

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from kof5_tts.api import app
from kof5_tts import local_studio
from kof5_tts.research import api as research_api
from kof5_tts.research.openrouter import OpenRouterError


class ResearchApiTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {"KOF5_RESEARCH_ENABLED": "1", "OPENROUTER_API_KEY": ""}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        network = patch("socket.socket.connect", side_effect=AssertionError("No network allowed"))
        network.start()
        self.addCleanup(network.stop)
        self.client = TestClient(app, base_url="http://127.0.0.1:8767")
        self.addCleanup(self.client.close)

    def test_offline_catalog_and_interview_without_login_or_provider(self):
        catalog = self.client.get("/research-api/catalog")
        self.assertEqual(catalog.status_code, 200)
        self.assertEqual(catalog.headers["Cache-Control"], "no-store")
        self.assertTrue(catalog.json()["cases"])
        response = self.client.post("/research-api/interview", json={"budget": 8})
        self.assertEqual(response.status_code, 200)
        question = response.json()["next_question"]
        answers = []
        for _ in range(8):
            answers.append({'question_id': question['id'], 'option_id': question['options'][0]['id']})
            result = self.client.post('/research-api/interview', json={'budget': 8, 'answers': answers})
            self.assertEqual(result.status_code, 200)
            question = result.json()['next_question']
        self.assertTrue(result.json()['done'])
        self.assertEqual(result.json()['reflected_count'], 8)
        self.assertTrue(result.json()['heldout_predictions'])

    def test_twelve_long_unicode_answers_fit_the_bounded_replay_contract(self):
        answers = []
        result = self.client.post('/research-api/interview', json={'budget': 12})
        for _ in range(12):
            answers.append({'question_id': result.json()['next_question']['id'], 'text': '가' * 500})
            result = self.client.post('/research-api/interview', content=json.dumps({'budget': 12, 'answers': answers}, ensure_ascii=True),
                                      headers={'Content-Type': 'application/json'})
            self.assertEqual(result.status_code, 200)
        self.assertTrue(result.json()['done'])
        self.assertEqual(len(result.json()['written_answers']), 12)

    def test_direct_input_is_bounded_and_explicit_annotation_only(self):
        question = self.client.post('/research-api/interview', json={}).json()['next_question']
        answer = {'question_id': question['id'], 'text': '<script>문장</script>'}
        result = self.client.post('/research-api/interview', json={'answers': [answer]})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['written_answers'][0]['text'], answer['text'])
        self.assertEqual(result.json()['reflected_count'], 0)
        answer['option_id'] = 'b'
        self.assertEqual(self.client.post('/research-api/interview', json={'answers': [answer]}).json()['reflected_count'], 1)
        for text in ['', '  ', 'x' * 501]:
            self.assertEqual(self.client.post('/research-api/interview', json={'answers': [{'question_id': question['id'], 'text': text}]}).status_code, 422)

    def test_free_interpretation_requires_consent_verified_guardian_and_saved_context(self):
        saved = {'profile': {'guardian_name': '가상 보호자', 'patient_alias': '가상 가족', 'relationship': '딸', 'address_as': '아빠', 'speech_style': 'mixed'},
                 'memories': [{'category': 'story'}]}
        body = {'text': '다시 고르고 싶구나. 어느 쪽이 좋아?', 'provider_processing_consent': True}
        interpreted = {'option_id': 'd', 'reason': '마음을 짚고 선택을 묻습니다.', 'model': 'fixed-free-model', 'cost': 0, 'attempts': [{'model': 'fixed-free-model', 'status': 'success'}]}
        with patch.object(local_studio, 'authorize', new_callable=AsyncMock) as authorize, \
             patch.object(local_studio, 'load', return_value=saved), \
             patch.object(research_api, 'classify_answer', return_value=interpreted) as classify:
            self.assertEqual(self.client.post('/research-api/interpret', json={**body, 'provider_processing_consent': False}).status_code, 422)
            authorize.assert_not_called()
            classify.assert_not_called()
            result = self.client.post('/research-api/interpret', json=body)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json()['answer']['text'], body['text'])
            self.assertEqual(result.json()['answer']['option_id'], 'd')
            self.assertEqual(result.json()['interview']['reflected_count'], 1)
            self.assertEqual(classify.call_count, 1)
            self.assertEqual(authorize.call_count, 1)
            classify.return_value = {**interpreted, 'option_id': None}
            result = self.client.post('/research-api/interpret', json=body)
            self.assertEqual(result.json()['interview']['reflected_count'], 0)
            self.assertNotIn('option_id', result.json()['answer'])
            saved['memories'] = []
            classify.reset_mock()
            self.assertEqual(self.client.post('/research-api/interpret', json=body).status_code, 409)
            classify.assert_not_called()

    def test_interpret_failure_returns_all_bounded_attempts(self):
        saved = {'profile': {'guardian_name': '가상 보호자', 'patient_alias': '가상 가족', 'relationship': '딸', 'address_as': '아빠', 'speech_style': 'mixed'},
                 'memories': [{'category': 'story'}]}
        attempts = [{'model': model, 'status': 'failed', 'error': '공급자 오류'} for model in list(research_api.FREE_MODELS)[:3]]
        with patch.object(local_studio, 'authorize', new_callable=AsyncMock), \
             patch.object(local_studio, 'load', return_value=saved), \
             patch.object(research_api, 'classify_answer', side_effect=OpenRouterError('3번 실패했습니다.', attempts=attempts)) as classify:
            response = self.client.post('/research-api/interpret', json={'text': '가상 답변', 'provider_processing_consent': True})
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json()['detail']['attempts'], attempts)
            self.assertEqual(classify.call_count, 1)
            classify.reset_mock()
            response = self.client.post('/research-api/interpret', json={'text': '가상 답변', 'provider_processing_consent': True, 'model': 'paid/model'})
            self.assertEqual(response.status_code, 422)
            classify.assert_not_called()

    def test_interpretation_does_not_bypass_guardian_authentication(self):
        with patch.object(research_api, 'classify_answer') as classify:
            self.assertEqual(self.client.post('/research-api/interpret', json={'text': '가상 답변', 'provider_processing_consent': True}).status_code, 403)
            classify.assert_not_called()

    def test_preview_accepts_only_bundled_cases_and_typed_style(self):
        case = self.client.get("/research-api/catalog").json()["cases"][0]
        response = self.client.post("/research-api/preview", json={"case_id": case["id"]})
        self.assertEqual(response.status_code, 200)
        self.assertIn("evidence_ids", response.json())
        self.assertNotIn("expected", response.json())
        self.assertEqual(self.client.post("/research-api/preview", json={"case_id": "unknown"}).status_code, 404)
        for body in [
            {"case_id": case["id"], "evidence": []},
            {"case_id": case["id"], "style": {"address": "arbitrary patient name"}},
        ]:
            self.assertEqual(self.client.post("/research-api/preview", json=body).status_code, 422)

    def test_default_off_vercel_remote_client_host_and_cross_origin_blocked(self):
        for env in [{"KOF5_RESEARCH_ENABLED": "0"}, {"VERCEL": "1"}]:
            with patch.dict(os.environ, env):
                for path in ["/research", "/research-api/catalog"]:
                    self.assertEqual(self.client.get(path).status_code, 403)
        for headers in [{"Host": "external.example"}, {"Origin": "https://external.example"}]:
            self.assertEqual(self.client.get("/research-api/catalog", headers=headers).status_code, 403)
        with TestClient(app, base_url="http://127.0.0.1", client=("192.0.2.1", 1234)) as remote:
            self.assertEqual(remote.get("/research-api/catalog").status_code, 403)

    def test_invalid_replays_bounds_and_oversized_body_fail_closed(self):
        for body in [
            {"budget": 0}, {"budget": 5}, {"budget": 13}, {"budget": True}, {"seed": -1},
            {"strategy": "other"}, {"answers": [{"question_id": "unknown", "option_id": "a"}]},
        ]:
            self.assertEqual(self.client.post("/research-api/interview", json=body).status_code, 422)
        response = self.client.post("/research-api/interview", content=b" " * 65_537,
                                    headers={"Content-Type": "application/json"})
        self.assertEqual(response.status_code, 413)


if __name__ == "__main__":
    unittest.main()
