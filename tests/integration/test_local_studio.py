"""Local-only MVP contract. Providers are fakes; no paid requests or patient data."""
import base64
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'src'))
from kof5_tts.api import app
from kof5_tts import local_studio as studio
from kof5_tts.cloud_prototype import EnrolledVoice
from tests.synthetic_wav import make_synthetic_wav


class LocalStudioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'KOF5_LOCAL_STUDIO': '1', 'KOF5_STUDIO_DB': str(Path(self.temp.name) / 'state.db'), 'ELEVENLABS_API_KEY': 'test-only', 'OPENAI_API_KEY': 'test-only'}, clear=True)
        self.env.start()
        self.client = TestClient(app, base_url='http://127.0.0.1', headers={'X-Kof5-Studio': '1'})

    def tearDown(self):
        self.client.close()
        self.env.stop()
        self.temp.cleanup()

    def setup_profile(self):
        return self.client.put('/local-studio/profile', json={'guardian_name': '시험자', 'patient_alias': '가상 가족', 'relationship': '딸', 'address_as': '아빠'})

    def setup_voice(self, status='created'):
        self.setup_profile()
        state = studio.load()
        state['voice'] = {'status': status, 'name': 'KoF5 internal self-voice test ' + 'a' * 32, 'voice_id': 'fakevoice'}
        studio.save(state)

    def sample_payload(self):
        wav = make_synthetic_wav(seconds=20)
        return {'own_voice_confirmed': True, 'provider_processing_consent': True, 'samples_wav_base64': [base64.b64encode(wav).decode()] * 3}

    def test_requires_opt_in_loopback_host_peer_and_origin_before_writing(self):
        for env in [{'KOF5_LOCAL_STUDIO': '0'}, {'VERCEL': '1'}]:
            with patch.dict(os.environ, env):
                self.assertEqual(self.client.get('/local-studio/state').status_code, 403)
        for headers in [{'Origin': 'https://other.example'}, {'Host': 'external.example'}, {'X-Kof5-Studio': ''}]:
            self.assertEqual(self.client.get('/local-studio/state', headers=headers).status_code, 403)
        with TestClient(app, base_url='http://127.0.0.1', client=('192.0.2.1', 1234), headers={'X-Kof5-Studio': '1'}) as remote:
            self.assertEqual(remote.get('/local-studio/state').status_code, 403)
        self.assertFalse(Path(os.environ['KOF5_STUDIO_DB']).exists())

    def test_profile_and_memory_persist_edit_delete_and_do_not_expose_secrets(self):
        self.assertEqual(self.setup_profile().status_code, 200)
        memory = {'title': '가상 여행', 'category': 'story', 'content': '제주도에서 흑돼지를 먹었다.'}
        result = self.client.post('/local-studio/memories', json=memory)
        self.assertEqual(result.status_code, 200)
        memory_id = result.json()['memories'][0]['id']
        self.assertEqual(self.client.put(f'/local-studio/memories/{memory_id}', json={**memory, 'content': '함께 산책했다.'}).status_code, 200)
        with TestClient(app, base_url='http://127.0.0.1', headers={'X-Kof5-Studio': '1'}) as reloaded:
            state = reloaded.get('/local-studio/state')
            self.assertEqual(state.json()['memories'][0]['content'], '함께 산책했다.')
            self.assertEqual(state.headers['cache-control'], 'no-store')
            self.assertNotIn('test-only', state.text)
            self.assertNotIn('voice_id', state.text)
        self.assertEqual(self.client.delete(f'/local-studio/memories/{memory_id}').json()['memories'], [])
        self.assertEqual(Path(os.environ['KOF5_STUDIO_DB']).stat().st_mode & 0o777, 0o600)

    def test_validation_limits_and_missing_provider(self):
        self.assertEqual(self.client.post('/local-studio/memories', json={'title': ' ', 'category': 'unknown', 'content': 'x'}).status_code, 422)
        self.assertEqual(self.client.post('/local-studio/voice', content=b'x' * (studio.MAX_BODY + 1)).status_code, 413)
        with patch.dict(os.environ, {'ELEVENLABS_API_KEY': ''}):
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).status_code, 503)
        payload = self.sample_payload()
        payload['own_voice_confirmed'] = False
        self.assertEqual(self.client.post('/local-studio/voice', json=payload).status_code, 422)

    def test_enrollment_persists_only_metadata_and_never_blindly_retries(self):
        self.setup_profile()
        with patch.object(studio, 'enroll_test_voice', return_value=EnrolledVoice('fakevoice', False)) as create:
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).json()['voice']['status'], 'created')
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).status_code, 409)
            self.assertEqual(create.call_count, 1)
        stored = studio.load()
        self.assertNotIn('samples', str(stored))
        stored['voice']['status'] = 'deleted'
        studio.save(stored)
        with patch.object(studio, 'enroll_test_voice', side_effect=httpx.ReadTimeout('test')) as create:
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).status_code, 502)
            self.assertEqual(studio.load()['voice']['status'], 'pending')
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).status_code, 409)
            self.assertEqual(create.call_count, 1)

    def test_explicit_provider_rejection_allows_retry_without_claiming_created(self):
        self.setup_profile()
        error = httpx.HTTPStatusError('denied', request=httpx.Request('POST', 'https://api.elevenlabs.io/v1/voices/add'), response=httpx.Response(401))
        with patch.object(studio, 'enroll_test_voice', side_effect=error):
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).status_code, 502)
        self.assertEqual(studio.load()['voice']['status'], 'failed')
        with patch.object(studio, 'enroll_test_voice', return_value=EnrolledVoice('fakevoice', False)):
            self.assertEqual(self.client.post('/local-studio/voice', json=self.sample_payload()).json()['voice']['status'], 'created')

    def test_reconcile_does_not_bypass_voice_verification(self):
        self.setup_voice('verification_pending')
        def respond(request):
            return httpx.Response(200, json={'voice_id': 'fakevoice', 'name': studio.load()['voice']['name'], 'voice_verification': {'requires_verification': True, 'is_verified': False}})
        real_client = httpx.Client
        with patch.object(studio.httpx, 'Client', side_effect=lambda **kw: real_client(transport=httpx.MockTransport(respond))):
            result = self.client.post('/local-studio/voice/reconcile')
        self.assertEqual(result.json()['voice']['status'], 'verification_pending')

    def test_conversation_needs_consent_memory_and_voice_then_returns_audio_without_persisting_turn(self):
        self.setup_voice()
        turn = {'text': '어디 갔었지?', 'provider_processing_consent': True}
        self.assertEqual(self.client.post('/local-studio/turn', json={**turn, 'provider_processing_consent': False}).status_code, 422)
        self.assertEqual(self.client.post('/local-studio/turn', json=turn).status_code, 409)
        self.client.post('/local-studio/memories', json={'title': '추억', 'category': 'story', 'content': '제주도에서 산책했다.'})
        with patch.object(studio, 'generate_short_reply', return_value='제주도에서 함께 산책했어요.') as reply, patch.object(studio, 'synthesize_mp3', return_value=b'fake-mp3') as tts:
            response = self.client.post('/local-studio/turn', json=turn)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(base64.b64decode(response.json()['audio_base64']), b'fake-mp3')
            self.assertIn('제주도', reply.call_args.args[2])
            self.assertEqual(tts.call_args.args[2].voice_id, 'fakevoice')
        self.assertNotIn(turn['text'], str(studio.load()))

    def test_transcription_is_optional_and_requires_audio_processing_consent(self):
        payload = {'wav_base64': base64.b64encode(make_synthetic_wav(seconds=1)).decode(), 'provider_processing_consent': True}
        self.assertEqual(self.client.post('/local-studio/transcribe', json=payload).status_code, 503)
        with patch.dict(os.environ, {'DEEPGRAM_API_KEY': 'fake-stt'}), patch.object(studio, 'transcribe_wav', return_value='제주도 기억나?') as transcribe:
            self.assertEqual(self.client.post('/local-studio/transcribe', json={**payload, 'provider_processing_consent': False}).status_code, 422)
            transcribe.assert_not_called()
            response = self.client.post('/local-studio/transcribe', json=payload)
            self.assertEqual(response.json(), {'text': '제주도 기억나?'})
        self.assertNotIn('제주도 기억나?', str(studio.load()))

    def test_delete_blocks_use_immediately_and_checks_remote_absence(self):
        self.setup_voice()
        with patch.object(studio, 'delete_test_voice'), patch.object(studio, 'test_voice_present', return_value=True):
            self.assertEqual(self.client.delete('/local-studio/voice').status_code, 502)
        self.assertEqual(studio.load()['voice']['status'], 'deletion_pending')
        with patch.object(studio, 'delete_test_voice'), patch.object(studio, 'test_voice_present', return_value=False):
            self.assertEqual(self.client.delete('/local-studio/voice').json()['voice']['status'], 'deleted')


if __name__ == '__main__':
    unittest.main()
