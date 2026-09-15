BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(26);

-- Pinned synthetic IDs only. Every fixture row rolls back below.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000971', false),
    ('00000000-0000-4000-8000-000000000972', true),
    ('00000000-0000-4000-8000-000000000973', true),
    ('00000000-0000-4000-8000-000000000974', false);
INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000975', 'TEST-HOSPITAL-TURN', 'TEST-P', '가상 환자', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000977', 'TEST-HOSPITAL-TURN', 'TEST-Q', '가상 다른 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status, admitted_at, discharged_at
) VALUES
    ('00000000-0000-4000-8000-000000000976', '00000000-0000-4000-8000-000000000975',
     'TEST-CURRENT', 'in_progress', now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000000979', '00000000-0000-4000-8000-000000000975',
     'TEST-OLD', 'finished', now() - interval '3 days', now() - interval '2 days'),
    ('00000000-0000-4000-8000-000000000978', '00000000-0000-4000-8000-000000000977',
     'TEST-OTHER', 'in_progress', now() - interval '1 day', NULL);
INSERT INTO kof5.hospital_registry_activation (
    hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref,
    approved_at, expires_at
) VALUES ('TEST-HOSPITAL-TURN', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY',
          now() - interval '1 day', now() + interval '1 day');
INSERT INTO kof5.hospital_staff_membership (
    membership_id, auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961',
          '00000000-0000-4000-8000-000000000971', 'TEST-HOSPITAL-TURN',
          'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment (
    membership_id, hospital_ref, patient_id, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-HOSPITAL-TURN',
          '00000000-0000-4000-8000-000000000975', 'verified',
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
     now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile (
    patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
    embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
    enrolled_by_staff_ref, enrolled_at
) VALUES ('00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000976',
          '00000000-0000-4000-8000-000000000953', 'active', 30000,
          'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted',
          'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment (
    device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at
) VALUES ('00000000-0000-4000-8000-000000000972',
          '00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000976',
          '00000000-0000-4000-8000-000000000971', now() + interval '2 hours');

INSERT INTO kof5.hospital_context_fact (
    patient_id, encounter_id, category, content, source_staff_ref,
    approved_by_staff_ref, verified_at, valid_until, status, revoked_at
) VALUES
    ('00000000-0000-4000-8000-000000000975', NULL, 'hospital',
     '가상 새봄병원입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', now() + interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'room', '가상 307호입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '2 hours', now() + interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'test_schedule', '가상 내일 오후 4시 CT 촬영 예정입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '3 hours', now() + interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'test_schedule', '가상 내일 오전 9시 MRI 촬영 예정입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '2 hours', now() + interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'test_schedule', '가상 혈액 검사는 오늘 14시입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', now() + interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'medication', '가상 약을 드세요.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', NULL, 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', NULL,
     'hospital', '가상 약 복용하세요.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', NULL, 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'room', '가상 승인 전 병실입니다.', 'TEST-SOURCE', NULL,
     NULL, NULL, 'draft', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'room', '가상 취소된 병실입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 day', NULL, 'revoked', now()),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'room', '가상 만료된 병실입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '2 days', now() - interval '1 day', 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000979',
     'room', '가상 이전 입원 병실입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '3 days', NULL, 'approved', NULL),
    ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
     'room', repeat('가', 201), 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', NULL, 'approved', NULL),
    ('00000000-0000-4000-8000-000000000977', '00000000-0000-4000-8000-000000000978',
     'room', '가상 다른 환자 병실입니다.', 'TEST-SOURCE', 'TEST-APPROVER',
     now() - interval '1 hour', NULL, 'approved', NULL);

SELECT ok(NOT has_function_privilege('anon',
    'api.patient_hospital_turn_context(uuid,text)', 'EXECUTE'),
    'signed-out role cannot call patient hospital turn');
SELECT ok(NOT has_function_privilege('service_role',
    'api.patient_hospital_turn_context(uuid,text)', 'EXECUTE'),
    'service role has no exposed hospital turn grant');
SELECT ok(has_function_privilege('authenticated',
    'api.patient_hospital_turn_context(uuid,text)', 'EXECUTE'),
    'signed-in device can call invoker hospital turn');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_context_fact', 'INSERT'),
    'device and guardian cannot author clinical facts');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_context_fact', 'UPDATE'),
    'device and guardian cannot approve or edit clinical facts');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc
    WHERE oid = 'api.patient_hospital_turn_context(uuid,text)'::regprocedure),
    'hospital turn is invoker and cannot bypass fact RLS');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '어느 병원인가요?')),
    'unlinked guardian cannot use patient hospital fact turn');
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 0,
    'guardian cannot enumerate staff hospital context view');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current), 0,
    'anonymous device cannot enumerate staff hospital context view');
SELECT is((SELECT count(*)::integer FROM kof5.hospital_context_fact), 5,
    'device fact RLS exposes only short approved current/safe-category rows');
SELECT is((SELECT count(*)::integer FROM kof5.hospital_context_fact
           WHERE content = '가상 약 복용하세요.'), 0,
    'miscategorized medication advice is hidden from device fact RLS');
SELECT is((SELECT count(*)::integer FROM api.patient_hospital_turn_context(
    '00000000-0000-4000-8000-000000000975', '어느 병원인가요?')), 1,
    'atomic hospital turn always returns exactly one eligibility row');
SELECT ok((SELECT authorized IS TRUE AND jsonb_array_length(facts) = 1
           AND facts->0->>'content' = '가상 새봄병원입니다.'
           AND facts->0->>'category' = 'hospital'
           AND facts->0->>'verified_at' IS NOT NULL
           AND facts->0->>'valid_until' IS NOT NULL
           AND facts->0->>'encounter_id' IS NULL
           AND facts->0 ? 'source_staff_ref' IS FALSE
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '어느 병원인가요?')),
    'hospital name turn keeps minimal provenance without staff identifier');
SELECT ok((SELECT authorized IS TRUE AND jsonb_array_length(facts) = 1
           AND facts->0->>'content' = '가상 307호입니다.'
           AND facts->0->>'encounter_id' = '00000000-0000-4000-8000-000000000976'
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '제 병실은 어디인가요?')),
    'room question selects current encounter, not draft/revoked/expired/old/long facts');
SELECT ok((SELECT authorized IS TRUE AND jsonb_array_length(facts) = 1
           AND facts->0->>'content' = '가상 내일 오후 4시 CT 촬영 예정입니다.'
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', 'CT 검사는 몇 시인가요?')),
    'CT question selects older CT original, not newer MRI schedule');
SELECT ok((SELECT authorized IS TRUE AND jsonb_array_length(facts) = 1
           AND facts->0->>'content' = '가상 혈액 검사는 오늘 14시입니다.'
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '혈액검사는 몇 시야?')),
    'Korean blood-test token matches approved original across spacing');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '검사는 언제인가요?')),
    'generic procedure question never guesses between CT and MRI schedules');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', 'CT 검사 결과 어때요?')),
    'CT result question cannot be answered with a CT schedule original');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '약을 드셔야 하나요?')),
    'treatment category is not voiced from hospital fact namespace');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '병원에서 약 처방은 어떻게 해요?')),
    'hospital-name original cannot answer a medication question');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '음악 좋아하세요?')),
    'authorized no-match hospital question differs from withdrawal');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000977', '병실은 어디인가요?')),
    'alternate real patient UUID stays default denied');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000973","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '병원 이름이 뭐예요?')),
    'unpaired anonymous device receives explicit unauthorized empty result');
RESET ROLE;

UPDATE kof5.patient_device_assignment
SET paired_at = now() - interval '3 hours', expires_at = now() - interval '1 hour'
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '어느 병원인가요?')),
    'expired device pairing removes hospital turn authorization');
RESET ROLE;
UPDATE kof5.patient_device_assignment
SET paired_at = now(), expires_at = now() + interval '2 hours'
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
UPDATE kof5.hospital_encounter SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '병실은 어디인가요?')),
    'finished encounter removes hospital turn authorization');
RESET ROLE;
UPDATE kof5.hospital_encounter SET status = 'in_progress', discharged_at = NULL
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000952';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '어느 병원인가요?')),
    'ambient consent withdrawal cannot appear as authorized no-match');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
