BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(19);

-- Only synthetic Auth users, patients, staff approval and message text; all rolled back.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-000000000801'),
    ('00000000-0000-4000-8000-000000000802'),
    ('00000000-0000-4000-8000-000000000803'),
    ('00000000-0000-4000-8000-000000000804');

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000901', 'TEST-H1', 'TEST-C1', '가상 환자 A', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000902', 'TEST-H1', 'TEST-C2', '가상 환자 B', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000903', 'TEST-H2', 'TEST-C3', '가상 환자 C', 'TEST-STAFF');

INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status, admitted_at, discharged_at
) VALUES
    ('00000000-0000-4000-8000-000000001001', '00000000-0000-4000-8000-000000000901',
     'TEST-CE1', 'in_progress', now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000001002', '00000000-0000-4000-8000-000000000902',
     'TEST-CE2', 'in_progress', now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000001003', '00000000-0000-4000-8000-000000000903',
     'TEST-CE3', 'in_progress', now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000001004', '00000000-0000-4000-8000-000000000901',
     'TEST-CE4', 'finished', now() - interval '3 days', now() - interval '2 days');

INSERT INTO kof5.hospital_staff_membership (
    membership_id, auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES
    ('00000000-0000-4000-8000-000000001101', '00000000-0000-4000-8000-000000000801',
     'TEST-H1', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000001102', '00000000-0000-4000-8000-000000000802',
     'TEST-H1', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000001103', '00000000-0000-4000-8000-000000000803',
     'TEST-H2', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());

INSERT INTO kof5.hospital_staff_assignment (
    membership_id, hospital_ref, patient_id, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES (
    '00000000-0000-4000-8000-000000001102', 'TEST-H1',
    '00000000-0000-4000-8000-000000000901', 'verified',
    now() - interval '1 day', 'TEST-VERIFY', now()
);

INSERT INTO kof5.patient_guardian_link (
    patient_id, guardian_user_id, relationship, access_status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES (
    '00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000000804',
    '가상 보호자', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()
);

INSERT INTO kof5.hospital_context_fact (
    patient_id, encounter_id, category, content, source_staff_ref,
    approved_by_staff_ref, verified_at, valid_until, status
) VALUES
    ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000001001',
     'scheduled_exam', '가상 CT 검사는 오후 3시에 예정돼 있습니다.', 'TEST-STAFF',
     'TEST-APPROVER', now() - interval '1 hour', NULL, 'approved'),
    ('00000000-0000-4000-8000-000000000902', '00000000-0000-4000-8000-000000001002',
     'room', '가상 다른 환자의 병실', 'TEST-STAFF',
     'TEST-APPROVER', now() - interval '1 hour', NULL, 'approved'),
    ('00000000-0000-4000-8000-000000000903', '00000000-0000-4000-8000-000000001003',
     'room', '가상 다른 기관의 병실', 'TEST-STAFF',
     'TEST-APPROVER', now() - interval '1 hour', NULL, 'approved'),
    ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000001001',
     'room', '미승인 초안', 'TEST-STAFF', NULL, NULL, NULL, 'draft'),
    ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000001001',
     'room', '만료된 사실', 'TEST-STAFF',
     'TEST-APPROVER', now() - interval '2 days', now() - interval '1 day', 'approved'),
    ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000001004',
     'room', '종료된 입원 사실', 'TEST-STAFF',
     'TEST-APPROVER', now() - interval '1 hour', NULL, 'approved');

INSERT INTO kof5.hospital_message (
    patient_id, encounter_id, approved_text, approved_by_staff_ref, approved_at, due_at
) VALUES
    ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000001001',
     '가상 검사는 오후 3시입니다. 준비해주세요!', 'TEST-APPROVER', now(), now() + interval '1 hour'),
    ('00000000-0000-4000-8000-000000000902', '00000000-0000-4000-8000-000000001002',
     '가상 다른 환자의 메시지', 'TEST-APPROVER', now(), now() + interval '1 hour'),
    ('00000000-0000-4000-8000-000000000903', '00000000-0000-4000-8000-000000001003',
     '가상 다른 기관의 메시지', 'TEST-APPROVER', now(), now() + interval '1 hour');

SELECT ok((SELECT count(*) FROM pg_class
    WHERE relnamespace = 'kof5'::regnamespace
      AND relname IN ('hospital_context_fact', 'hospital_message')
      AND relrowsecurity AND relforcerowsecurity) = 2,
    'both hospital content tables enforce RLS');
SELECT ok(NOT has_table_privilege('anon', 'api.hospital_context_current', 'SELECT')
       AND NOT has_table_privilege('anon', 'api.hospital_message_list', 'SELECT'),
    'signed-out clients cannot read hospital content views');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_context_fact', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'kof5.hospital_message', 'INSERT'),
    'staff clients cannot create unverified facts or messages');
SELECT ok((SELECT count(*) FROM pg_class
    WHERE oid IN ('api.hospital_context_current'::regclass, 'api.hospital_message_list'::regclass)
      AND reloptions @> ARRAY['security_invoker=true']) = 2,
    'both hospital views execute with caller RLS');

SELECT lives_ok($sql$
    DO $do$ BEGIN
        BEGIN
            INSERT INTO kof5.hospital_context_fact (
                patient_id, encounter_id, category, content, source_staff_ref, status
            ) VALUES (
                '00000000-0000-4000-8000-000000000901',
                '00000000-0000-4000-8000-000000001002',
                'room', '교차 환자 사실', 'TEST-STAFF', 'draft'
            );
            RAISE EXCEPTION 'cross-patient encounter was accepted';
        EXCEPTION WHEN foreign_key_violation THEN NULL;
        END;
    END $do$
$sql$, 'context fact cannot attach another patient encounter');

SELECT lives_ok($sql$
    DO $do$ BEGIN
        BEGIN
            INSERT INTO kof5.hospital_message (
                patient_id, encounter_id, approved_text, approved_by_staff_ref,
                approved_at, due_at
            ) VALUES (
                '00000000-0000-4000-8000-000000000901',
                '00000000-0000-4000-8000-000000001002',
                '교차 환자 메시지', 'TEST-APPROVER', now(), now()
            );
            RAISE EXCEPTION 'cross-patient message encounter was accepted';
        EXCEPTION WHEN foreign_key_violation THEN NULL;
        END;
    END $do$
$sql$, 'hospital message cannot attach another patient encounter');

SELECT lives_ok($sql$
    DO $do$ BEGIN
        BEGIN
            INSERT INTO kof5.hospital_context_fact (
                patient_id, category, content, source_staff_ref, status
            ) VALUES (
                '00000000-0000-4000-8000-000000000901',
                'room', '미확인 승인', 'TEST-STAFF', 'approved'
            );
            RAISE EXCEPTION 'unverified fact was approved';
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END $do$
$sql$, 'approved context requires approver and verification time');

SELECT lives_ok($sql$
    DO $do$ BEGIN
        BEGIN
            INSERT INTO kof5.hospital_message (
                patient_id, encounter_id, approved_text, approved_by_staff_ref,
                approved_at, due_at, delivery_status
            ) VALUES (
                '00000000-0000-4000-8000-000000000901',
                '00000000-0000-4000-8000-000000001001',
                '전달 시각 없는 메시지', 'TEST-APPROVER', now(), now(), 'delivered'
            );
            RAISE EXCEPTION 'delivered message without timestamp was accepted';
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END $do$
$sql$, 'delivered message requires delivery timestamp');

SELECT lives_ok($sql$
    DO $do$ BEGIN
        BEGIN
            UPDATE kof5.hospital_message
            SET approved_text = '승인 후 변조된 메시지'
            WHERE approved_text = '가상 검사는 오후 3시입니다. 준비해주세요!';
            RAISE EXCEPTION 'approved message wording was mutable';
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END $do$
$sql$, 'approved hospital message wording is immutable');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000801', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 2,
    'H1 registrar sees only current approved H1 facts');
SELECT is((SELECT count(*)::integer FROM api.hospital_message_list), 2,
    'H1 registrar sees only H1 current messages');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000802', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 1,
    'assigned care staff sees only one approved current fact');
SELECT is((SELECT content FROM api.hospital_context_current LIMIT 1),
    '가상 CT 검사는 오후 3시에 예정돼 있습니다.',
    'care staff receives the verified hospital fact unchanged');
SELECT is((SELECT count(*)::integer FROM api.hospital_message_list), 1,
    'assigned care staff sees only their patient message');
SELECT is((SELECT approved_text FROM api.hospital_message_list LIMIT 1),
    '가상 검사는 오후 3시입니다. 준비해주세요!',
    'staff-approved message punctuation and wording are unchanged');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000803', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 1,
    'H2 registrar sees only H2 facts');
SELECT is((SELECT count(*)::integer FROM api.hospital_message_list), 1,
    'H2 registrar sees only H2 message');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000804', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 0,
    'verified guardian cannot read hospital facts');
SELECT is((SELECT count(*)::integer FROM api.hospital_message_list), 0,
    'verified guardian cannot read hospital messages');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
