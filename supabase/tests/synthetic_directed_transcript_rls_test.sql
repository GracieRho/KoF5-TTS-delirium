BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(34);

-- Pinned synthetic IDs only. Every fixture row rolls back below.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000971', false),
    ('00000000-0000-4000-8000-000000000972', true),
    ('00000000-0000-4000-8000-000000000973', true),
    ('00000000-0000-4000-8000-000000000974', false);
INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000975', 'TEST-TODAY-TRANSCRIPT', 'TEST-P', '가상 환자', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000977', 'TEST-TODAY-TRANSCRIPT', 'TEST-Q', '가상 다른 환자', 'TEST-STAFF');
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
) VALUES ('TEST-TODAY-TRANSCRIPT', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY',
          now() - interval '1 day', now() + interval '1 day');
INSERT INTO kof5.hospital_staff_membership (
    membership_id, auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961',
          '00000000-0000-4000-8000-000000000971', 'TEST-TODAY-TRANSCRIPT',
          'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment (
    membership_id, hospital_ref, patient_id, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-TODAY-TRANSCRIPT',
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

SELECT ok(NOT has_function_privilege('anon',
    'api.record_synthetic_directed_turn(uuid,uuid,text)', 'EXECUTE'),
    'signed-out role cannot call record RPC');
SELECT ok(NOT has_function_privilege('service_role',
    'api.record_synthetic_directed_turn(uuid,uuid,text)', 'EXECUTE'),
    'service role cannot call exposed record RPC');
SELECT ok(has_function_privilege('authenticated',
    'api.record_synthetic_directed_turn(uuid,uuid,text)', 'EXECUTE'),
    'paired device can call invoker RPC');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.record_synthetic_directed_turn(uuid,uuid,text)'::regprocedure),
    'exposed record RPC is invoker');
SELECT ok(NOT has_table_privilege('authenticated',
    'kof5.synthetic_directed_turn', 'UPDATE'),
    'staff and device cannot edit transcript');
SELECT ok(NOT has_table_privilege('authenticated',
    'kof5.synthetic_directed_turn', 'DELETE'),
    'staff and device cannot delete transcript');
SELECT is((SELECT relforcerowsecurity FROM pg_class WHERE oid =
    'kof5.synthetic_directed_turn'::regclass), true,
    'synthetic transcript table forces RLS');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), false,
    'unlinked permanent guardian cannot record');
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'guardian cannot read assigned staff today view');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), false,
    'assigned permanent staff cannot spoof device recording');
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'staff sees no synthetic transcript before a directed turn');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000973', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000973","is_anonymous":true}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), false,
    'unpaired anonymous user cannot record');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000977',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), false,
    'other patient UUID is default denied');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975', NULL, '가상 환자 질문'), false,
    'missing client turn ID is denied');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000942', '  '), false,
    'empty canonical text is denied');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000942', repeat('가', 501)), false,
    'oversized text is denied');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', ' 가상 환자 질문 '), true,
    'current paired device records bounded canonical directed text');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), true,
    'same UUID and same canonical text is idempotent');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '다른 가상 질문'), false,
    'same UUID with conflicting text is denied');
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'device cannot read staff transcript view');
SELECT is((SELECT count(*)::integer FROM kof5.synthetic_directed_turn), 0,
    'device cannot enumerate base transcript rows');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 1,
    'assigned verified permanent staff sees one current directed turn');
SELECT is((SELECT transcript FROM api.synthetic_today_transcript LIMIT 1),
    '가상 환자 질문', 'staff view contains only canonical patient text');
SELECT ok((SELECT captured_at <= now() AND captured_at >=
    (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul')
        AT TIME ZONE 'Asia/Seoul')
    FROM api.synthetic_today_transcript LIMIT 1),
    'staff view is bounded to KST today');

RESET ROLE;
-- Previous-encounter and yesterday rows are privileged setup only.
INSERT INTO kof5.synthetic_directed_turn (
    patient_id, encounter_id, device_user_id, client_turn_id, transcript,
    captured_at, expires_at
) VALUES
    ('00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000979',
     '00000000-0000-4000-8000-000000000972',
     '00000000-0000-4000-8000-000000000943', '가상 이전 입원', now(),
     (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') + interval '1 day')
        AT TIME ZONE 'Asia/Seoul'),
    ('00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000976',
     '00000000-0000-4000-8000-000000000972',
     '00000000-0000-4000-8000-000000000944', '가상 어제 질문',
     (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul')
        AT TIME ZONE 'Asia/Seoul') - interval '1 hour',
     date_trunc('day', now() AT TIME ZONE 'Asia/Seoul')
        AT TIME ZONE 'Asia/Seoul');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 1,
    'previous encounter and expired yesterday text stay hidden');
RESET ROLE;
SET ROLE service_role;
SELECT is(kof5.purge_expired_synthetic_directed_turns(), 1,
    'service-only trusted sweep removes one expired row');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.synthetic_directed_turn
    WHERE client_turn_id = '00000000-0000-4000-8000-000000000944'), 0,
    'trusted explicit sweep physically removes expired text');

SAVEPOINT revoked_pairing;
UPDATE kof5.patient_device_assignment SET status = 'revoked', revoked_at = now()
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000945', '가상 철회 장치 질문'), false,
    'revoked pairing denies recording');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'revoked pairing immediately hides stored text from staff');
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_pairing;

SAVEPOINT expired_pairing;
UPDATE kof5.patient_device_assignment SET paired_at = now() - interval '2 hours',
    expires_at = now() - interval '1 hour'
WHERE device_user_id = '00000000-0000-4000-8000-000000000972';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000945', '가상 만료 장치 질문'), false,
    'expired pairing denies recording');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'expired pairing hides stored text from staff');
RESET ROLE;
ROLLBACK TO SAVEPOINT expired_pairing;

RESET ROLE;
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000952';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000945', '철회 후 가상 질문'), false,
    'consent withdrawal denies a new write');
SELECT is(api.record_synthetic_directed_turn(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941', '가상 환자 질문'), false,
    'consent withdrawal denies even identical replay');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_today_transcript), 0,
    'withdrawal immediately hides existing text from staff');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
