"""Single-operator, loopback-only voice MVP; never a patient service."""
from __future__ import annotations

from base64 import b64decode, b64encode
from datetime import datetime, timezone
from contextlib import contextmanager
import json
from hashlib import sha256
import os
from pathlib import Path
import sqlite3
from threading import RLock
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, Field

from kof5_tts.cloud_prototype import (
    CloudCredentials, delete_test_voice, enroll_test_voice, find_test_voice,
    generate_short_reply, synthesize_mp3, test_voice_present, transcribe_wav,
    validate_test_voice_samples,
)

LOCK = RLock()
MAX_BODY = 8_100_000


async def authorize(request: Request) -> None:
    host = request.url.hostname
    origin = request.headers.get('origin')
    if (os.environ.get('KOF5_LOCAL_STUDIO') != '1' or os.environ.get('VERCEL')
            or host not in {'127.0.0.1', 'localhost', '::1'}
            or not request.client or request.client.host not in {'127.0.0.1', '::1', 'testclient'}
            or request.headers.get('x-kof5-studio') != '1'
            or (origin and origin != f'{request.url.scheme}://{request.url.netloc}')):
        raise HTTPException(403, '로컬 시연 서버에서만 사용할 수 있습니다.')

    owner = os.environ.get('KOF5_STUDIO_GUARDIAN_USER_ID', '')
    url = os.environ.get('KOF5_SUPABASE_URL', '').rstrip('/')
    key = os.environ.get('KOF5_SUPABASE_PUBLISHABLE_KEY', '')
    token = request.headers.get('authorization', '')
    if not owner or url != 'http://127.0.0.1:54341' or not key.startswith('sb_publishable_'):
        raise HTTPException(503, '보호자 계정 연결이 아직 준비되지 않았습니다.')
    if not token.startswith('Bearer ') or not 10 < len(token) < 8192:
        raise HTTPException(401, '보호자 로그인이 필요합니다.')
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.post(f'{url}/rest/v1/rpc/portal_access', headers={
                'apikey': key, 'Authorization': token, 'Content-Profile': 'api'}, json={})
        if response.status_code in (401, 403):
            raise HTTPException(401, '로그인을 다시 확인해주세요.')
        response.raise_for_status()
        access = response.json()
    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(503, '로그인 권한을 확인하지 못했습니다.') from error
    if not isinstance(access, dict) or not access.get('guardian') or access.get('user_id') != owner:
        raise HTTPException(403, '이 보호자 공간에 접근할 수 없습니다.')


class StudioRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def bounded(request: Request):
            await authorize(request)
            body = bytearray()
            async for chunk in request.stream():
                if len(body) + len(chunk) > MAX_BODY:
                    raise HTTPException(413, '음성 자료가 너무 큽니다.')
                body.extend(chunk)
            request._body = bytes(body)
            response = await handler(request)
            response.headers['Cache-Control'] = 'no-store'
            return response
        return bounded


router = APIRouter(prefix='/local-studio', route_class=StudioRoute)


@contextmanager
def database():
    # shortcut: one configured guardian/process; migrate workspace ownership before adding more guardians.
    path = Path(os.environ.get('KOF5_STUDIO_DB', 'runs/local-studio/workspace.sqlite3'))
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    connection = sqlite3.connect(path)
    path.chmod(0o600)
    connection.execute('CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY CHECK(id=1), body TEXT NOT NULL)')
    try:
        with connection:
            connection.execute('CREATE TABLE IF NOT EXISTS workspace_owner (id INTEGER PRIMARY KEY CHECK(id=1), user_id TEXT NOT NULL)')
            owner = os.environ.get('KOF5_STUDIO_GUARDIAN_USER_ID', '')
            existing = connection.execute('SELECT user_id FROM workspace_owner WHERE id=1').fetchone()
            if existing and existing[0] != owner:
                raise HTTPException(409, '다른 보호자의 저장 공간입니다. 서버 설정을 확인해주세요.')
            if not existing and owner:
                connection.execute('INSERT INTO workspace_owner VALUES (1, ?)', (owner,))
            yield connection
    finally:
        connection.close()


def load() -> dict:
    with database() as connection:
        row = connection.execute('SELECT body FROM workspace WHERE id=1').fetchone()
    return json.loads(row[0]) if row else {
        'profile': {'guardian_name': '', 'patient_alias': '', 'relationship': '', 'address_as': ''},
        'memories': [], 'voice': {'status': 'none', 'voice_id': None, 'name': None},
    }


def save(state: dict) -> None:
    with database() as connection:
        connection.execute('INSERT INTO workspace VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
                           (json.dumps(state, ensure_ascii=False),))


def public_state(state: dict) -> dict:
    return {**state, 'voice': {'status': state['voice']['status']}, 'providers': {
        'voice': bool(os.environ.get('ELEVENLABS_API_KEY')),
        'conversation': bool(os.environ.get('OPENAI_API_KEY')),
        'transcription': bool(os.environ.get('DEEPGRAM_API_KEY')),
    }}


def provider_key(name: str) -> str:
    key = os.environ.get(name, '')
    if not key:
        raise HTTPException(503, f'서버의 {name} 설정이 필요합니다.')
    return key


class StudioInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")


class Profile(StudioInput):
    guardian_name: str = Field(min_length=1, max_length=40)
    patient_alias: str = Field(min_length=1, max_length=40)
    relationship: str = Field(min_length=1, max_length=40)
    address_as: str = Field(min_length=1, max_length=40)


class Memory(StudioInput):
    title: str = Field(min_length=1, max_length=80)
    category: str = Field(pattern='^(family|story|comfort|avoid)$')
    content: str = Field(min_length=1, max_length=1200)


class Enrollment(StudioInput):
    own_voice_confirmed: bool
    provider_processing_consent: bool
    samples_wav_base64: list[str] = Field(min_length=3, max_length=3)


class Turn(StudioInput):
    text: str = Field(min_length=1, max_length=500)
    provider_processing_consent: bool


class AudioInput(StudioInput):
    wav_base64: str = Field(min_length=1, max_length=2_700_000)
    provider_processing_consent: bool


@router.get('/state')
def state():
    with LOCK:
        return public_state(load())


@router.put('/profile')
def profile(payload: Profile):
    with LOCK:
        current = load()
        current['profile'] = payload.model_dump()
        save(current)
        return public_state(current)


@router.post('/memories')
def add_memory(payload: Memory):
    with LOCK:
        current = load()
        if len(current['memories']) >= 30:
            raise HTTPException(409, '시연 기억은 최대 30개까지 저장합니다.')
        current['memories'].append({**payload.model_dump(), 'id': str(uuid4()), 'created_at': datetime.now(timezone.utc).isoformat()})
        save(current)
        return public_state(current)


@router.put('/memories/{memory_id}')
def edit_memory(memory_id: str, payload: Memory):
    with LOCK:
        current = load()
        for memory in current['memories']:
            if memory['id'] == memory_id:
                memory.update(payload.model_dump())
                save(current)
                return public_state(current)
        raise HTTPException(404, '기억을 찾을 수 없습니다.')


@router.delete('/memories/{memory_id}')
def remove_memory(memory_id: str):
    with LOCK:
        current = load()
        current['memories'] = [m for m in current['memories'] if m['id'] != memory_id]
        save(current)
        return public_state(current)


@router.post('/voice')
def enroll(payload: Enrollment):
    if not payload.own_voice_confirmed or not payload.provider_processing_consent:
        raise HTTPException(422, '본인 음성과 ElevenLabs 전송 동의를 확인하세요.')
    key = provider_key('ELEVENLABS_API_KEY')
    try:
        if any(len(sample) > 2_700_000 for sample in payload.samples_wav_base64):
            raise ValueError('sample too large')
        samples = [b64decode(sample, validate=True) for sample in payload.samples_wav_base64]
        validate_test_voice_samples(samples)
    except ValueError:
        raise HTTPException(422, 'PCM16 WAV 20~30초 샘플 세 개가 필요합니다.') from None
    with LOCK:
        current = load()
        if not all(current['profile'].values()):
            raise HTTPException(409, '가족 소개를 먼저 저장하세요.')
        if current['voice']['status'] not in {'none', 'failed', 'deleted'}:
            raise HTTPException(409, '기존 음성 상태를 확인하세요. 중복 생성하지 않습니다.')
        name = f'KoF5 internal self-voice test {uuid4().hex}'
        current['voice'] = {'status': 'pending', 'name': name, 'voice_id': None}
        save(current)
        try:
            with httpx.Client(timeout=60) as client:
                voice = enroll_test_voice(client, samples, key, True, name)
            current['voice'].update(voice_id=voice.voice_id,
                                    status='created' if voice.requires_verification is False else 'verification_pending')
            save(current)
        except httpx.HTTPStatusError as error:
            if error.response.status_code in {400, 401, 402, 403, 413, 415, 422}:
                current['voice']['status'] = 'failed'
                save(current)
                raise HTTPException(502, '공급자가 등록을 거절했습니다. 키·요금제·샘플 조건을 확인한 뒤 다시 시도하세요.') from None
            raise HTTPException(502, '생성 결과를 확인하지 못했습니다. 원격 상태를 확인하세요.') from None
        except (httpx.HTTPError, ValueError):
            raise HTTPException(502, '생성 결과를 확인하지 못했습니다. 재업로드 대신 원격 상태를 확인하세요.') from None
        return public_state(current)


@router.post('/voice/reconcile')
def reconcile():
    key = provider_key('ELEVENLABS_API_KEY')
    with LOCK:
        current = load()
        voice = current['voice']
        if voice['status'] not in {'pending', 'verification_pending'}:
            return public_state(current)
        try:
            with httpx.Client(timeout=30) as client:
                found = voice['voice_id'] or find_test_voice(client, voice['name'], key)
                if found:
                    response = client.get(f'https://api.elevenlabs.io/v1/voices/{found}', headers={'xi-api-key': key})
                    response.raise_for_status()
                    detail = response.json()
                    if not isinstance(detail, dict) or detail.get('voice_id') != found or detail.get('name') != voice['name']:
                        raise ValueError('voice identity differs')
                    verification = detail.get('voice_verification') or {}
                    if not isinstance(verification, dict):
                        raise ValueError('invalid verification status')
                    usable = verification.get('requires_verification') is False or verification.get('is_verified') is True
                    voice.update(voice_id=found, status='created' if usable else 'verification_pending')
                    save(current)
        except (httpx.HTTPError, ValueError):
            raise HTTPException(502, '원격 상태를 확인하지 못했습니다.') from None
        return public_state(current)


@router.delete('/voice')
def delete_voice():
    key = provider_key('ELEVENLABS_API_KEY')
    with LOCK:
        current = load()
        voice = current['voice']
        if voice['status'] in {'none', 'deleted'}:
            return public_state(current)
        voice['status'] = 'deletion_pending'
        save(current)
        try:
            with httpx.Client(timeout=30) as client:
                if not voice['voice_id']:
                    voice['voice_id'] = find_test_voice(client, voice['name'], key)
                    save(current)
                if not voice['voice_id']:
                    raise ValueError('creation outcome unknown')
                delete_test_voice(client, voice['voice_id'], key)
                if test_voice_present(client, voice['voice_id'], key):
                    raise ValueError('voice still present')
            voice['status'] = 'deleted'
            save(current)
        except (httpx.HTTPError, ValueError):
            raise HTTPException(502, '사용을 중단했습니다. 원격 삭제 완료는 아직 확인되지 않았습니다.') from None
        return public_state(current)


@router.post('/turn')
def turn(payload: Turn):
    if not payload.provider_processing_consent:
        raise HTTPException(422, '기억·질문의 OpenAI 전송과 답변의 ElevenLabs 전송에 동의하세요.')
    openai_key = provider_key('OPENAI_API_KEY')
    voice_key = provider_key('ELEVENLABS_API_KEY')
    with LOCK:
        current = load()
        if current['voice']['status'] != 'created':
            raise HTTPException(409, '사용 가능한 복제 음성을 먼저 등록하세요.')
        memories = [m for m in current['memories'] if m['category'] != 'avoid']
        if not memories:
            raise HTTPException(409, '가족 기억을 먼저 입력하세요.')
        # shortcut: at most 30 short memories in context; measure Korean retrieval before a larger collection.
        facts = json.dumps({'family': current['profile'], 'memories': memories,
                           'avoid_topics': [m['content'] for m in current['memories'] if m['category'] == 'avoid']}, ensure_ascii=False)
        credentials = CloudCredentials('', openai_key, voice_key, current['voice']['voice_id'], True)
        try:
            with httpx.Client(timeout=60) as client:
                reply = generate_short_reply(client, payload.text, facts, openai_key, extra_instructions=' family의 호칭과 관계를 참고하되 가족 본인이라고 주장하지 않는다. avoid_topics는 대화에서 꺼내지 않는다. 질문과 관련 없는 기억을 나열하지 않는다. 질문에 대한 정보가 없으면 지어내지 않고 확인된 기억이 없다고 말한다.')
                audio = synthesize_mp3(client, reply, credentials)
        except (httpx.HTTPError, ValueError):
            raise HTTPException(502, '답변 또는 음성을 만들지 못했습니다. 설정과 공급자 상태를 확인하세요.') from None
        return {'reply': reply, 'audio_base64': b64encode(audio).decode(), 'memory_count': len(memories)}


@router.post('/transcribe')
def transcribe(payload: AudioInput):
    if not payload.provider_processing_consent:
        raise HTTPException(422, '녹음의 Deepgram 전송에 동의하세요.')
    key = provider_key('DEEPGRAM_API_KEY')
    try:
        wav = b64decode(payload.wav_base64, validate=True)
        with httpx.Client(timeout=30) as client:
            text = transcribe_wav(client, wav, key)
        return {'text': text}
    except (httpx.HTTPError, ValueError):
        raise HTTPException(502, '질문을 전사하지 못했습니다. 직접 입력할 수 있습니다.') from None


class MaterialSubmission(StudioInput):
    patient_id: UUID
    encounter_id: UUID
    sharing_consent: bool


@router.post('/hospital-materials')
def submit_hospital_material(payload: MaterialSubmission, request: Request):
    if not payload.sharing_consent:
        raise HTTPException(422, '병원에 소개·기억·음성 등록 상태를 보내는 데 동의하세요.')
    with LOCK:
        current = load()
        if not all(current['profile'].values()) or not current['memories']:
            raise HTTPException(409, '가족 소개와 기억을 먼저 저장하세요.')
        # Only an opaque revision leaves the voice store, never the provider voice ID.
        revision = sha256(json.dumps(current['voice'], sort_keys=True).encode()).hexdigest()
        try:
            with httpx.Client(timeout=15) as client:
                response = client.post(os.environ['KOF5_SUPABASE_URL'] + '/rest/v1/rpc/submit_family_material',
                    headers={'apikey': os.environ['KOF5_SUPABASE_PUBLISHABLE_KEY'],
                             'Authorization': request.headers['authorization'], 'Content-Profile': 'api'},
                    json={'_patient': str(payload.patient_id), '_encounter': str(payload.encounter_id),
                          '_profile': current['profile'], '_memories': current['memories'],
                          '_voice_status': current['voice']['status'], '_voice_revision': revision})
            if response.status_code in (401, 403):
                raise HTTPException(403, '현재 입원의 보호자 연결을 확인해주세요.')
            response.raise_for_status()
            material_id = str(UUID(response.json()))
        except (httpx.HTTPError, ValueError, TypeError):
            raise HTTPException(502, '자료 전송 결과를 확인하지 못했습니다. 제출 목록을 다시 조회해주세요.') from None
        return {'material_id': material_id}
