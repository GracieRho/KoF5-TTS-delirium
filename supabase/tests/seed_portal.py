"""로컬 전용 가상 계정·환자 초기 자료. 재실행은 기존 편집 내용을 보존한다."""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
import sys
from uuid import UUID, NAMESPACE_URL, uuid5

from local_http_smoke import ROOT, local_keys, request, sql, verify_local_target

PATIENT = '00000000-0000-4000-8000-000000000976'
HOSPITAL = 'TEST-FAVILIUM'


def identifier(name: str) -> str:
    return str(uuid5(NAMESPACE_URL, 'favilium-local-portal/' + name))


def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys['API_URL'], keys['PUBLISHABLE_KEY'], keys['SERVICE_ROLE_KEY']
    users = {}
    for role, email in [('guardian', 'guardian@email.com'), ('hospital', 'hospital@email.com')]:
        found = sql(f'SELECT id FROM auth.users WHERE email={literal(email)};')
        if not found:
            status, user = request(f'{url}/auth/v1/admin/users', 'POST', admin,
                                   payload={'email': email, 'password': 'test1234', 'email_confirm': True})
            assert status in (200, 201), f'{role} create failed: {status}'
            found = user['id']
        users[role] = str(UUID(found))
    fixture = json.loads((ROOT / 'supabase/fixtures/portal.json').read_text())
    statements = ['BEGIN;']
    for index, patient in enumerate(fixture['patients']):
        pid = PATIENT if index == 0 else identifier(f'patient-{index}')
        eid = identifier(f'encounter-{index}')
        statements.append(f"""
          INSERT INTO kof5.hospital_patient (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
          VALUES ('{pid}','{HOSPITAL}','TEST-FV-{index+1:03}',{literal(patient['name'])},'TEST-SEED') ON CONFLICT DO NOTHING;
          INSERT INTO kof5.hospital_encounter (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at,ward_ref,room_ref,bed_ref,location_verified_at)
          VALUES ('{eid}','{pid}','TEST-ENC-{index+1:03}','in_progress',now()-interval '2 days',{literal(patient['ward'])},{literal(patient['room'])},{literal(patient['bed'])},now()) ON CONFLICT DO NOTHING;
        """)
        for category, content in [('hospital','파빌리움 가상 병원입니다.'), ('room', f"{patient['ward']} {patient['room']} {patient['bed']}입니다."), ('visit_schedule',patient['visit'])]:
            statements.append(f"""INSERT INTO kof5.hospital_context_fact (fact_id,patient_id,encounter_id,category,content,source_staff_ref,approved_by_staff_ref,verified_at,status)
              VALUES ('{identifier(f'fact-{index}-{category}')}','{pid}','{eid}',{literal(category)},{literal(content)},'TEST-SEED','TEST-APPROVER',now(),'approved') ON CONFLICT DO NOTHING;""")
        for message_index, content in enumerate([patient['visit'], '필요한 것이 있으면 호출 버튼을 눌러 간호사를 불러주세요.']):
            delivered = message_index == 1 and index != 0
            statements.append(f"""INSERT INTO kof5.hospital_message (message_id,patient_id,encounter_id,approved_text,approved_by_staff_ref,approved_at,due_at,delivery_status,delivered_at)
              VALUES ('{identifier(f'message-{index}-{message_index}')}','{pid}','{eid}',{literal(content)},'TEST-APPROVER',now()-interval '1 hour',now()+interval '{index*15} minutes',{'\'delivered\'' if delivered else '\'pending\''},{'now()' if delivered else 'NULL'}) ON CONFLICT DO NOTHING;""")
    statements.append(f"""
      INSERT INTO kof5.hospital_staff_membership (membership_id,auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
      VALUES ('{identifier('membership')}','{users['hospital']}','{HOSPITAL}','registrar','verified',now()-interval '1 minute','TEST-VERIFY',now()) ON CONFLICT DO NOTHING;
      INSERT INTO kof5.patient_guardian_link (patient_id,guardian_user_id,relationship,access_status,effective_at,verified_by_staff_ref,verified_at)
      VALUES ('{PATIENT}','{users['guardian']}','딸','verified',now()-interval '1 minute','TEST-VERIFY',now()) ON CONFLICT DO NOTHING;
    """)
    for index, memory in enumerate(fixture['memories']):
        category = 'avoid_topic' if memory['category'] == 'avoid' else 'favorite_story'
        statements.append(f"""INSERT INTO kof5.family_fact (fact_id,patient_id,author_guardian_user_id,category,content)
          VALUES ('{identifier(f'memory-{index}')}','{PATIENT}','{users['guardian']}',{literal(category)},{literal(memory['content'])}) ON CONFLICT DO NOTHING;""")
    statements.append('COMMIT;')
    try:
        sql('\n'.join(statements))
    except subprocess.CalledProcessError as error:
        raise RuntimeError(error.stderr) from None
    runtime = ROOT / 'runs/local-studio'
    runtime.mkdir(parents=True, exist_ok=True)
    env_path = runtime / 'portal.env'
    env_path.write_text(f"KOF5_LOCAL_STUDIO=1\nKOF5_STUDIO_DB={runtime / 'portal-workspace.sqlite3'}\nKOF5_SUPABASE_URL={url}\nKOF5_SUPABASE_PUBLISHABLE_KEY={public}\nKOF5_STUDIO_GUARDIAN_USER_ID={users['guardian']}\n")
    env_path.chmod(0o600)
    sys.path.insert(0, str(ROOT / 'src'))
    from kof5_tts import local_studio
    os.environ['KOF5_STUDIO_GUARDIAN_USER_ID'] = users['guardian']
    os.environ['KOF5_STUDIO_DB'] = str(runtime / 'portal-workspace.sqlite3')
    state = local_studio.load()
    if not state['profile']['guardian_name'] and not state['memories']:
        state['profile'] = fixture['profile']
        state['memories'] = [{**m, 'id': identifier(f'studio-memory-{i}'), 'created_at': '2026-10-15T00:00:00+00:00'} for i,m in enumerate(fixture['memories'])]
        local_studio.save(state)
    for role, email in [('guardian','guardian@email.com'),('hospital','hospital@email.com')]:
        status, session = request(f'{url}/auth/v1/token?grant_type=password','POST',public,payload={'email':email,'password':'test1234'})
        assert status == 200, f'{role} login failed: {status}'
        token = session['access_token']
        status, access = request(f'{url}/rest/v1/rpc/portal_access','POST',public,token,payload={},schema='api')
        assert status == 200 and access[role], f'{role} role failed: {status}'
        status, _ = request(f'{url}/auth/v1/logout?scope=local','POST',public,token)
        assert status == 204, f'{role} seed session logout failed: {status}'
    print('가상 계정 2개 · 환자 6명 · 승인 사실 18건 · 메시지 12건 · 가족 기억 6건 준비 완료')


if __name__ == '__main__':
    main()
