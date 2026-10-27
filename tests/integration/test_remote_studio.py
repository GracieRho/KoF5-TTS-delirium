"""Cloud workspace contracts, isolated from real services and provider billing."""
import copy
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from fastapi import HTTPException
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'src'))
from kof5_tts.api import app
from kof5_tts import local_studio as studio

OWNER = '00000000-0000-4000-8000-000000000901'
OTHER = '00000000-0000-4000-8000-000000000902'


class RemoteStudioTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'VERCEL': '1', 'KOF5_REMOTE_STUDIO': '1',
            'KOF5_SUPABASE_URL': 'https://dedicated.supabase.co', 'KOF5_SUPABASE_PROJECT_REF': 'dedicated',
            'KOF5_SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test',
            'KOF5_SUPABASE_SECRET_KEY': 'sb_secret_test'}, clear=True)
        self.env.start()
        self.auth = patch.object(httpx.AsyncClient, 'post', new_callable=AsyncMock)
        self.auth_call = self.auth.start()
        self.set_access(OWNER)
        self.rows = {}
        self.rpc = patch.object(studio, 'workspace_rpc', side_effect=self.store)
        self.rpc_call = self.rpc.start()
        self.local = patch.object(studio, 'database', side_effect=AssertionError('cloud must never use SQLite'))
        self.local.start()
        self.client = TestClient(app, base_url='https://favilium.example',
            headers={'X-Kof5-Studio': '1', 'Authorization': 'Bearer test-session-token'})

    def tearDown(self):
        self.client.close()
        self.local.stop()
        self.rpc.stop()
        self.auth.stop()
        self.env.stop()

    def set_access(self, owner, guardian=True):
        self.auth_call.return_value = httpx.Response(200,
            json={'user_id': owner, 'guardian': guardian, 'hospital': not guardian},
            request=httpx.Request('POST', 'https://dedicated.supabase.co'))

    def store(self, name, payload):
        owner = payload['_guardian']
        if name == 'load_guardian_workspace':
            return copy.deepcopy(self.rows.get(owner))
        row = self.rows.get(owner)
        revision = row['revision'] if row else 0
        if payload['_expected'] != revision:
            raise HTTPException(409, 'workspace changed')
        self.rows[owner] = {'revision': revision + 1, 'body': copy.deepcopy(payload['_body'])}
        return revision + 1

    def test_persists_per_verified_guardian_and_hides_provider_metadata(self):
        profile = {'guardian_name': '가상 보호자', 'patient_alias': '가상 가족', 'relationship': '딸', 'address_as': '아빠', 'address_aliases': ['아버지'], 'speech_style': 'mixed'}
        self.assertEqual(self.client.put('/local-studio/profile', json=profile).status_code, 200)
        self.rows[OWNER]['body']['voice'] = {'status': 'pending', 'voice_id': 'private-provider-id', 'name': 'private-name'}
        result = self.client.get('/local-studio/state')
        self.assertEqual(result.json()['profile'], profile)
        self.assertNotIn('private-provider-id', result.text)
        self.assertNotIn('private-name', result.text)
        self.set_access(OTHER)
        self.assertEqual(self.client.get('/local-studio/state').json()['profile']['guardian_name'], '')
        self.assertIsNone(studio.REMOTE_STORE.get())

    def test_rejects_staff_cross_origin_missing_session_and_bad_project(self):
        self.set_access(OWNER, guardian=False)
        self.assertEqual(self.client.get('/local-studio/state').status_code, 403)
        self.set_access(OWNER)
        self.assertEqual(self.client.get('/local-studio/state', headers={'Authorization': ''}).status_code, 401)
        self.assertEqual(self.client.get('/local-studio/state', headers={'Origin': 'https://other.example'}).status_code, 403)
        with patch.dict(os.environ, {'KOF5_SUPABASE_URL': 'https://other.supabase.co'}):
            self.assertEqual(self.client.get('/local-studio/state').status_code, 503)
        self.rpc_call.assert_not_called()

    def test_conflict_is_visible_and_request_context_is_reset(self):
        self.rpc_call.side_effect = HTTPException(409, '다른 화면에서 자료가 변경됐습니다.')
        self.assertEqual(self.client.get('/local-studio/state').status_code, 409)
        self.assertIsNone(studio.REMOTE_STORE.get())

    def test_rpc_uses_server_key_and_preserves_conflict_or_outage(self):
        self.rpc.stop()
        try:
            with patch.object(studio.httpx, 'Client') as factory:
                post = factory.return_value.__enter__.return_value.post
                post.return_value = httpx.Response(409, request=httpx.Request('POST', 'https://dedicated.supabase.co'))
                with self.assertRaises(HTTPException) as error:
                    studio.workspace_rpc('save_guardian_workspace', {'_guardian': OWNER})
                self.assertEqual(error.exception.status_code, 409)
                self.assertEqual(post.call_args.kwargs['headers']['apikey'], 'sb_secret_test')
                post.side_effect = httpx.ConnectError('offline')
                with self.assertRaises(HTTPException) as error:
                    studio.workspace_rpc('load_guardian_workspace', {'_guardian': OWNER})
                self.assertEqual(error.exception.status_code, 503)
        finally:
            self.rpc.start()
