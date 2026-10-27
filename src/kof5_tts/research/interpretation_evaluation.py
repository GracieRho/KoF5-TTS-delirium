"""실제 보호자 인증과 HTTP 경로로 가상 문장 분류를 평가한다."""
import hashlib
import json
from pathlib import Path
import time
from urllib.parse import urlsplit

import httpx

from kof5_tts.research.interview import load_question_bank
from kof5_tts.research.openrouter import FREE_MODELS


def load_cases(path: Path) -> dict:
    data = json.loads(path.read_text())
    questions = {q['id']: q for q in load_question_bank()['questions'] if q['split'] == 'elicitation'}
    cases = data.get('cases', [])
    if not 1 <= len(cases) <= 100 or len({c['id'] for c in cases}) != len(cases):
        raise ValueError('평가 문장은 고유 ID를 가진 1–100개여야 합니다.')
    for case in cases:
        question = questions.get(case['question_id'])
        if (not question or not isinstance(case['text'], str) or not 1 <= len(case['text'].strip()) <= 500
                or case['expected_option_id'] not in [None, *[o['id'] for o in question['options']]]):
            raise ValueError('질문·문장·기대 선택지를 확인해주세요.')
    return data


def summarize(rows: list[dict]) -> dict:
    completed = [row for row in rows if row['status'] == 'success']
    correct = sum(row['predicted_option_id'] == row['expected_option_id'] for row in completed)
    return {'total': len(rows), 'completed': len(completed), 'errors': len(rows) - len(completed),
            'correct': correct, 'accuracy_completed': correct / len(completed) if completed else None,
            'correct_over_all_requests': correct / len(rows) if rows else None,
            'model_attempts': sum(len(row.get('attempts', [])) for row in rows),
            'reported_cost': sum(row.get('cost', 0) for row in completed)}


def evaluate(base_url: str, email: str, password: str, cases_path: Path, output: Path,
             model: str, consent: bool, progress=print) -> dict:
    target = urlsplit(base_url)
    if (target.scheme != 'http' or target.hostname != '127.0.0.1' or not target.port
            or target.username or target.password or target.path or target.query or target.fragment):
        raise ValueError('명시적으로 켠 http://127.0.0.1:포트 서버만 평가합니다.')
    if model not in FREE_MODELS or not consent:
        raise ValueError('등록된 무료 모델과 합성 문장 전송 동의가 필요합니다.')
    cases = load_cases(cases_path)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    rows = []
    with httpx.Client(timeout=100, follow_redirects=False) as client:
        config_response = client.get(base_url + '/portal/config')
        config_response.raise_for_status()
        config = config_response.json()
        if config['url'] != 'http://127.0.0.1:54341':
            raise ValueError('프로젝트 전용 로컬 Auth 연결만 허용합니다.')
        auth_headers = {'apikey': config['publishable_key']}
        login = client.post(config['url'] + '/auth/v1/token?grant_type=password',
                            headers=auth_headers, json={'email': email, 'password': password})
        if login.status_code != 200:
            raise ValueError(f'보호자 로그인 실패: HTTP {login.status_code}')
        token = login.json()['access_token']
        headers = {'Authorization': 'Bearer ' + token, 'X-Kof5-Studio': '1', 'Origin': base_url}
        try:
            saved = client.get(base_url + '/local-studio/state', headers=headers)
            saved.raise_for_status()
            family = saved.json()
            profile = family['profile']
            if not profile.get('speech_style') or not family['memories']:
                raise ValueError('가족의 기억에서 말투와 기억을 먼저 준비해주세요.')
            # Follow the public fixed-order replay; never supply an arbitrary question to the model.
            prefixes = {}
            answers = []
            for _ in range(8):
                response = client.post(base_url + '/research-api/interview', json={'strategy': 'fixed', 'budget': 8, 'answers': answers})
                response.raise_for_status()
                q = response.json()['next_question']
                prefixes[q['id']] = list(answers)
                answers.append({'question_id': q['id'], 'option_id': q['options'][0]['id']})
            for case in cases['cases']:
                started = time.perf_counter()
                response = client.post(base_url + '/research-api/interpret', headers=headers,
                                       json={'strategy': 'fixed', 'budget': 8, 'answers': prefixes[case['question_id']],
                                             'text': case['text'], 'model': model, 'provider_processing_consent': True})
                row = {**case, 'http_status': response.status_code, 'elapsed_ms': round((time.perf_counter() - started) * 1000, 2)}
                if response.status_code == 200:
                    result = response.json()
                    interpretation = result['interpretation']
                    if interpretation['cost'] != 0 or not 1 <= len(interpretation['attempts']) <= 3:
                        raise ValueError('0원 비용 또는 시도 상한을 확인하지 못해 배치를 중단했습니다.')
                    assert result['answer']['question_id'] == case['question_id']
                    assert result['answer']['text'] == case['text']
                    row.update(status='success', predicted_option_id=interpretation['option_id'],
                               model=interpretation['model'], cost=interpretation['cost'], attempts=interpretation['attempts'])
                elif response.status_code == 503:
                    detail = response.json().get('detail', {})
                    attempts = detail.get('attempts', []) if isinstance(detail, dict) else []
                    if not isinstance(detail, dict) or detail.get('fatal') is not False or len(attempts) != 3:
                        raise ValueError('공통 연결·비용 오류로 배치를 중단했습니다.')
                    row.update(status='error', attempts=attempts)
                else:
                    raise ValueError(f'인증·자료·입력 오류로 배치를 중단했습니다: HTTP {response.status_code}')
                rows.append(row)
                path = output / 'responses.jsonl'
                path.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
                path.chmod(0o600)
                progress(f"{len(rows)}/{len(cases['cases'])} {case['id']}: {row['status']}")
        finally:
            logout = client.post(config['url'] + '/auth/v1/logout?scope=local', headers={**auth_headers, 'Authorization': 'Bearer ' + token})
            if logout.status_code != 204:
                progress('평가용 세션 로그아웃 확인 실패')
    report = {'cases_version': cases['version'], 'cases_sha256': hashlib.sha256(cases_path.read_bytes()).hexdigest(),
              'selected_model': model, 'auth': 'real-local-supabase', 'storage': 'existing-guardian-workspace',
              'memory_count': len(family['memories']), 'summary': summarize(rows),
              'limitation': cases['description']}
    (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report
