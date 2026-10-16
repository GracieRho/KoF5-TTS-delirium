"""실제 로컬 Auth·RLS·역할·로그아웃 토큰 폐기·Studio 경계 검사."""
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from local_http_smoke import local_keys, request, verify_local_target


def studio_status(token: str | None) -> int:
    headers = {'X-Kof5-Studio':'1'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    try:
        response = urlopen(Request('http://127.0.0.1:8766/local-studio/state', headers=headers), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        return response.status


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public = keys['API_URL'], keys['PUBLISHABLE_KEY']
    assert studio_status(None) == 401
    for role, email in [('guardian','guardian@email.com'),('hospital','hospital@email.com')]:
        status, session = request(f'{url}/auth/v1/token?grant_type=password','POST',public,payload={'email':email,'password':'test1234'})
        assert status == 200, f'{role} login: {status}'
        token = session['access_token']
        try:
            status, access = request(f'{url}/rest/v1/rpc/portal_access','POST',public,token,payload={},schema='api')
            assert status == 200 and access[role] and not access['hospital' if role == 'guardian' else 'guardian']
            status, patients = request(f'{url}/rest/v1/hospital_patient_list?select=patient_id','GET',public,token,schema='api')
            assert status == 200 and len(patients) == (6 if role == 'hospital' else 0)
            status, links = request(f'{url}/rest/v1/guardian_links?select=patient_id','GET',public,token,schema='api')
            assert status == 200 and len(links) == (1 if role == 'guardian' else 0)
            for path, expected in [('hospital_context_current?select=fact_id',18), ('hospital_message_list?select=message_id',12), ('family_context?select=fact_id',6)]:
                status, rows = request(f'{url}/rest/v1/{path}','GET',public,token,schema='api')
                count = (6 if role == 'guardian' else 0) if path.startswith('family_context') else (expected if role == 'hospital' else 0)
                assert status == 200 and len(rows) == count, f'{role} {path}: {status}, {len(rows)}'
            assert studio_status(token) == (200 if role == 'guardian' else 403)
        finally:
            status, _ = request(f'{url}/auth/v1/logout?scope=local','POST',public,token)
            assert status == 204, f'{role} logout: {status}'
        for path in ['hospital_patient_list?select=patient_id','guardian_links?select=patient_id','family_context?select=fact_id']:
            status, _ = request(f'{url}/rest/v1/{path}','GET',public,token,schema='api')
            assert status == 401, f'revoked {role} {path}: {status}'
        status, _ = request(f'{url}/rest/v1/family_context?fact_id=eq.26606533-ccab-5b5c-8fb3-42a0946f3199','PATCH',public,token,payload={'content':'must never be stored'},schema='api')
        assert status == 401
        assert studio_status(token) in (401,403)
    print('실제 로그인·역할 분리·RLS 환자 범위·Studio 직접 접근·로그아웃 후 GET/PATCH 토큰 재사용 차단: PASS')


if __name__ == '__main__':
    main()
