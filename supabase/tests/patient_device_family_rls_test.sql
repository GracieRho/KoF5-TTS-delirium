BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(50);

-- All rows are synthetic and rolled back. The pinned fixture is never a patient.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000971', false), -- assigned care staff
    ('00000000-0000-4000-8000-000000000972', true),  -- paired device
    ('00000000-0000-4000-8000-000000000973', true),  -- unpaired device
    ('00000000-0000-4000-8000-000000000974', false), -- guardian
    ('00000000-0000-4000-8000-000000000970', false); -- unassigned staff

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000975', 'TEST-D1', 'TEST-DEVICE', '가상 환자', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000977', 'TEST-D1', 'TEST-OTHER', '가상 다른 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status, admitted_at
) VALUES
    ('00000000-0000-4000-8000-000000000976', '00000000-0000-4000-8000-000000000975',
     'TEST-E1', 'in_progress', now() - interval '1 day'),
    ('00000000-0000-4000-8000-000000000978', '00000000-0000-4000-8000-000000000977',
     'TEST-E2', 'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation (
    hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref,
    approved_at, expires_at
) VALUES ('TEST-D1', 'approved', 'TEST-INSTITUTION', 'TEST-CLINICAL',
          now() - interval '1 day', now() + interval '1 day');

INSERT INTO kof5.hospital_staff_membership (
    membership_id, auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961',
          '00000000-0000-4000-8000-000000000971', 'TEST-D1', 'care_staff',
          'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment (
    membership_id, hospital_ref, patient_id, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-D1',
          '00000000-0000-4000-8000-000000000975', 'verified',
          now() - interval '1 day', 'TEST-VERIFY', now()),
         ('00000000-0000-4000-8000-000000000961', 'TEST-D1',
          '00000000-0000-4000-8000-000000000977', 'verified',
          now() - interval '1 day', 'TEST-VERIFY', now());

INSERT INTO kof5.consent_record (
    consent_id, patient_id, scope, signer_role, signer_ref,
    assent_status, status, effective_at, recorded_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000951', '00000000-0000-4000-8000-000000000975',
     'patient_participation', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000952', '00000000-0000-4000-8000-000000000975',
     'ambient_processing', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000953', '00000000-0000-4000-8000-000000000975',
     'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000954', '00000000-0000-4000-8000-000000000977',
     'patient_participation', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000955', '00000000-0000-4000-8000-000000000977',
     'ambient_processing', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000956', '00000000-0000-4000-8000-000000000977',
     'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile (
    patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
    embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
    enrolled_by_staff_ref, enrolled_at
) VALUES ('00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000976',
          '00000000-0000-4000-8000-000000000953', 'active', 30000,
          'TEST-MODEL', 'TEST-VERSION', 'TEST-FAKE-NOT-A-VOICE', 'accepted',
          'TEST-STAFF', now() - interval '1 day'),
         ('00000000-0000-4000-8000-000000000977',
          '00000000-0000-4000-8000-000000000978',
          '00000000-0000-4000-8000-000000000956', 'active', 30000,
          'TEST-MODEL', 'TEST-VERSION', 'TEST-OTHER-NOT-A-VOICE', 'accepted',
          'TEST-STAFF', now() - interval '1 day');

INSERT INTO kof5.patient_guardian_link (
    patient_id, guardian_user_id, relationship, access_status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000974', '가상 가족',
          'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
         ('00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000972', '가상 잘못 발급된 연결',
          'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.family_fact (
    patient_id, author_guardian_user_id, category, content, sensitivity,
    valid_from, active
) VALUES
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000974',
     'travel', '2024년 5월 제주도에 함께 갔었다.', 'ordinary', now() - interval '1 day', true),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000974',
     'avoid_topic', '제주도 사고는 피한다.', 'ordinary', now() - interval '1 day', true),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000974',
     'friend', '제주도 민감 정보', 'sensitive', now() - interval '1 day', true),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000972',
     'family', '가상 장치오류 기억', 'ordinary', now() - interval '1 day', true);

SELECT ok(NOT has_table_privilege('anon', 'api.patient_device_context', 'SELECT'),
    'signed-out role cannot read device context');
SELECT ok(NOT has_table_privilege('anon', 'api.synthetic_device_pairing_ready', 'SELECT'),
    'signed-out role cannot read staff pairing readiness');
SELECT ok(NOT has_function_privilege('anon', 'api.patient_family_search(uuid,text)', 'EXECUTE'),
    'signed-out role cannot search patient family facts');
SELECT ok(NOT has_function_privilege('anon', 'api.patient_family_turn_context(uuid,text)', 'EXECUTE'),
    'signed-out role cannot call atomic turn context');
SELECT ok(NOT has_function_privilege('service_role', 'api.patient_family_turn_context(uuid,text)', 'EXECUTE'),
    'service role has no exposed atomic turn grant');
SELECT ok(has_function_privilege('authenticated', 'api.patient_family_turn_context(uuid,text)', 'EXECUTE'),
    'authenticated device role has only invoker atomic turn grant');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.patient_device_assignment', 'UPDATE'),
    'clients cannot change or revoke pairing themselves');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
           FROM pg_class WHERE oid = 'api.patient_device_context'::regclass),
    'device context uses caller RLS');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc
               WHERE oid = 'api.patient_family_search(uuid,text)'::regprocedure),
    'patient search is invoker and does not bypass fact RLS');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc
               WHERE oid = 'api.patient_family_turn_context(uuid,text)'::regprocedure),
    'atomic turn context is invoker and does not bypass device RLS');
SELECT is((SELECT count(*)::integer FROM kof5.voice_profile_with_trial_consents
           WHERE patient_id = '00000000-0000-4000-8000-000000000977'), 1,
    'alternate synthetic patient satisfies all voice/participation/ambient prerequisites');
SELECT ok(NOT kof5.device_trial_ready(
    '00000000-0000-4000-8000-000000000977',
    '00000000-0000-4000-8000-000000000978'),
    'fixture-only gate denies alternate ID despite complete prerequisites');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000970', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000970","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_device_pairing_ready), 0,
    'unassigned staff has no pairing-ready patient');
SELECT throws_ok($sql$INSERT INTO api.patient_device_pairing
    (device_user_id, patient_id, encounter_id, expires_at)
    VALUES ('00000000-0000-4000-8000-000000000973',
            '00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', now() + interval '2 hours')
$sql$, '42501', 'new row violates row-level security policy for table "patient_device_assignment"',
    'unassigned staff cannot pair a device');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_device_pairing_ready), 1,
    'verified assigned permanent care staff sees synthetic pairing readiness');
SELECT throws_ok($sql$INSERT INTO api.patient_device_pairing
    (device_user_id, patient_id, encounter_id, expires_at)
    VALUES ('00000000-0000-4000-8000-000000000973',
            '00000000-0000-4000-8000-000000000977',
            '00000000-0000-4000-8000-000000000978', now() + interval '2 hours')
$sql$, '42501', 'new row violates row-level security policy for table "patient_device_assignment"',
    'real patient UUID cannot pass synthetic pairing gate');
SELECT lives_ok($sql$INSERT INTO api.patient_device_pairing
    (device_user_id, patient_id, encounter_id, expires_at)
    VALUES ('00000000-0000-4000-8000-000000000972',
            '00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', now() + interval '2 hours')
$sql$, 'verified assigned care staff can pair one anonymous device');
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 0,
    'staff cannot read device-owned context');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 1,
    'paired anonymous device sees only own current encounter');
SELECT is((SELECT count(*)::integer FROM api.synthetic_device_pairing_ready), 0,
    'anonymous device cannot see staff pairing form eligibility');
SELECT is((SELECT count(*)::integer FROM api.family_context), 0,
    'existing guardian view cannot enumerate device-readable facts');
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000975', '장치오류')), 0,
    'misissued guardian link cannot expose device-authored fact through guardian RPC');
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '장치오류 알려줘')), 0,
    'patient search excludes even preexisting device-authored facts');
SELECT throws_ok($sql$INSERT INTO api.family_context
    (patient_id, author_guardian_user_id, category, content)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000972', 'family', '잘못 쓴 기억')
$sql$, '42501', 'new row violates row-level security policy "permanent_guardian_only_family_fact_insert" for table "family_fact"',
    'misissued guardian link cannot let anonymous device add a memory');
WITH view_changed AS (
    UPDATE api.family_context SET content = '잘못 수정한 기억'
    WHERE author_guardian_user_id = '00000000-0000-4000-8000-000000000972'
    RETURNING fact_id
) SELECT is((SELECT count(*)::integer FROM view_changed), 0,
    'guardian edit view blocks anonymous device update');
WITH base_changed AS (
    UPDATE kof5.family_fact SET content = '직접 잘못 수정한 기억'
    WHERE author_guardian_user_id = '00000000-0000-4000-8000-000000000972'
    RETURNING fact_id
) SELECT is((SELECT count(*)::integer FROM base_changed), 0,
    'restrictive RLS also blocks direct private-table update');
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')), 1,
    'full Korean question retrieves synthetic 제주도 family fact');
SELECT is((SELECT content FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '제주도는 언제 갔었어?') LIMIT 1),
    '2024년 5월 제주도에 함께 갔었다.',
    'same-place inflection returns ordinary fact only');
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '음악 좋아하셨어?')), 0,
    'unrelated question has no family fact');
SELECT is((SELECT count(*)::integer FROM api.patient_family_turn_context(
    '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')), 1,
    'atomic turn always returns exactly one eligibility row');
SELECT ok((SELECT authorized IS TRUE AND facts = jsonb_build_array(
    jsonb_build_object('category', 'travel', 'content', '2024년 5월 제주도에 함께 갔었다.'))
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'authorized synthetic turn includes one ordinary permanent-guardian fact');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '음악 좋아하셨어?')),
    'authorized no-match turn is distinguishable from withdrawn eligibility');
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000977', '제주도 언제 갔었어?')), 0,
    'other patient UUID never retrieves a fact');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000977', '제주도 언제 갔었어?')),
    'other patient UUID never receives authorized turn context');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000973","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 0,
    'unpaired anonymous user cannot read context');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'unpaired anonymous user receives explicit unauthorized empty context');
SELECT throws_ok($sql$INSERT INTO api.patient_device_pairing
    (device_user_id, patient_id, encounter_id, expires_at)
    VALUES ('00000000-0000-4000-8000-000000000973',
            '00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', now() + interval '2 hours')
$sql$, '42501', 'new row violates row-level security policy for table "patient_device_assignment"',
    'anonymous user cannot pair itself');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.family_fact
           WHERE author_guardian_user_id = '00000000-0000-4000-8000-000000000972'
             AND content = '가상 장치오류 기억'), 1,
    'misissued-link edit attempts left original memory intact');
SELECT throws_ok($sql$UPDATE kof5.patient_device_assignment
    SET patient_id = '00000000-0000-4000-8000-000000000977'
    WHERE device_user_id = '00000000-0000-4000-8000-000000000972'
$sql$, '23514', 'device binding is immutable',
    'privileged writer cannot move a paired device to another patient');

UPDATE kof5.patient_guardian_link
SET access_status = 'revoked', revoked_at = now()
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')), 0,
    'guardian link revocation removes the family fact immediately');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'guardian revocation removes facts while device turn remains authorized');
RESET ROLE;
UPDATE kof5.patient_guardian_link
SET access_status = 'verified', revoked_at = NULL
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974';

UPDATE kof5.patient_device_assignment
SET paired_at = now() - interval '3 hours', expires_at = now() - interval '1 hour'
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 0,
    'expired pairing denies device context');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'expired pairing makes entire turn explicitly unauthorized');
RESET ROLE;
UPDATE kof5.patient_device_assignment
SET paired_at = now(), expires_at = now() + interval '2 hours'
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SAVEPOINT synthetic_revoked_pairing;
UPDATE kof5.patient_device_assignment
SET status = 'revoked', revoked_at = now()
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 0,
    'revoked pairing denies context');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'revoked pairing makes atomic turn explicitly unauthorized');
RESET ROLE;
SELECT throws_ok($sql$UPDATE kof5.patient_device_assignment
    SET status = 'active', revoked_at = NULL
    WHERE device_user_id = '00000000-0000-4000-8000-000000000972'
$sql$, '23514', 'revoked device requires new Auth user and pairing',
    'revoked pairing cannot be reactivated');
ROLLBACK TO SAVEPOINT synthetic_revoked_pairing;
UPDATE kof5.hospital_encounter
SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_family_search(
    '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')), 0,
    'finished encounter denies retrieval');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'finished encounter makes atomic turn explicitly unauthorized');
RESET ROLE;
UPDATE kof5.hospital_encounter
SET status = 'in_progress', discharged_at = NULL
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000952';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.patient_device_context), 0,
    'ambient consent withdrawal denies device context immediately');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_turn_context(
        '00000000-0000-4000-8000-000000000975', '제주도 언제 갔었어?')),
    'ambient consent withdrawal cannot masquerade as authorized no-match');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
