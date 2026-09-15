BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(33);

-- Fixture 975 is a synthetic sentinel, not a patient. This transaction rolls back.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false), -- proposer
    ('00000000-0000-4000-8000-000000000992', false), -- distinct approver
    ('00000000-0000-4000-8000-000000000993', false), -- unassigned staff
    ('00000000-0000-4000-8000-000000000994', true),  -- paired iPad
    ('00000000-0000-4000-8000-000000000995', true),  -- unpaired iPad
    ('00000000-0000-4000-8000-000000000996', false); -- guardian
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-MSG-H', 'TEST-P975', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-E975', 'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at)
VALUES ('TEST-MSG-H', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY', now() - interval '1 day');
INSERT INTO kof5.hospital_staff_membership
    (membership_id, auth_user_id, hospital_ref, product_role, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000991',
        'TEST-MSG-H', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', '00000000-0000-4000-8000-000000000992',
        'TEST-MSG-H', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000963', '00000000-0000-4000-8000-000000000994',
        'TEST-MSG-H', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment
    (membership_id, hospital_ref, patient_id, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-MSG-H',
        '00000000-0000-4000-8000-000000000975', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', 'TEST-MSG-H',
        '00000000-0000-4000-8000-000000000975', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981', '00000000-0000-4000-8000-000000000975',
        'patient_participation', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000982', '00000000-0000-4000-8000-000000000975',
        'ambient_processing', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983', '00000000-0000-4000-8000-000000000975',
        'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile
    (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
     embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
     enrolled_by_staff_ref, enrolled_at)
VALUES ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983', 'active', 30000,
        'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted', 'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment
    (device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at)
VALUES ('00000000-0000-4000-8000-000000000994', '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976', '00000000-0000-4000-8000-000000000991',
        now() + interval '2 hours');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity
           FROM pg_class WHERE oid = 'kof5.synthetic_hospital_message_draft'::regclass),
    'draft table enforces RLS');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
           FROM pg_class WHERE oid = 'api.synthetic_hospital_message_draft'::regclass),
    'draft Data API view uses caller RLS');
SELECT ok(NOT has_table_privilege('anon', 'api.synthetic_hospital_message_draft', 'INSERT'),
    'signed-out role cannot propose');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_message', 'INSERT'),
    'authenticated clients cannot insert approved messages directly');
SELECT ok(NOT has_function_privilege('anon', 'api.synthetic_due_hospital_message_ids(uuid)', 'EXECUTE'),
    'signed-out role cannot discover due IDs');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc
    WHERE oid = 'api.synthetic_due_hospital_message(uuid,uuid)'::regprocedure),
    'per-ID device RPC is invoker');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000993', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000993","is_anonymous":false}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', '가상 무담당 문구', 'now')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', '가상 익명 문구', 'now')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":false}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', '가상 보호자 문구', 'now')
$sql$, '42501');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 1,
    'permanent assigned staff still sees their fixture patient');
SELECT lives_ok($sql$INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', '오늘 오후 4시에 가상 CT 촬영 예정입니다.', 'now')
$sql$, 'assigned proposer can create an exact synthetic draft');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode, requested_due_at)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976',
            '예약 시간이 지난 가상 문구', 'scheduled', now() - interval '1 minute')
$sql$, '23514');
SELECT is((SELECT count(*)::integer FROM api.synthetic_hospital_message_draft), 1,
    'assigned proposer can review current synthetic draft');
WITH self_approval AS (
    UPDATE api.synthetic_hospital_message_draft SET status = 'approved'
    WHERE proposed_text = '오늘 오후 4시에 가상 CT 촬영 예정입니다.' RETURNING draft_id
) SELECT is((SELECT count(*)::integer FROM self_approval), 0,
    'proposer cannot self-approve');
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 0,
    'permanent staff JWT cannot discover device due messages');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000992', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000992","is_anonymous":false}', true);
SELECT lives_ok($sql$UPDATE api.synthetic_hospital_message_draft SET status = 'approved'
    WHERE proposed_text = '오늘 오후 4시에 가상 CT 촬영 예정입니다.'
$sql$, 'distinct assigned approver promotes exact text into pending message');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.hospital_message
           WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 1,
    'approval creates exactly one current-encounter message');
SELECT is((SELECT approved_text FROM kof5.hospital_message
           WHERE patient_id = '00000000-0000-4000-8000-000000000975'),
    '오늘 오후 4시에 가상 CT 촬영 예정입니다.', 'approved wording is byte-for-byte unchanged');
SELECT is((SELECT approved_by_staff_ref FROM kof5.hospital_message
           WHERE patient_id = '00000000-0000-4000-8000-000000000975'),
    '00000000-0000-4000-8000-000000000992', 'approver Auth ID comes from session');
SELECT is((SELECT delivery_status FROM kof5.hospital_message
           WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 'pending',
    'approval queues pending and never marks delivery');
SELECT ok((SELECT due_at = approved_at FROM kof5.hospital_message
           WHERE patient_id = '00000000-0000-4000-8000-000000000975'),
    'immediate approval becomes due at approval time');

-- Future scheduled text must not be offered as due until its DB time arrives.
INSERT INTO kof5.hospital_message
    (message_id, patient_id, encounter_id, approved_text, approved_by_staff_ref,
     approved_at, due_at)
VALUES ('00000000-0000-4000-8000-000000000999',
        '00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
        '내일 가상 검사 예정입니다.', 'TEST-APPROVER', now(), now() + interval '1 day');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 0,
    'misissued anonymous registrar cannot enumerate staff patient list');
SELECT is((SELECT count(*)::integer FROM api.hospital_message_list), 0,
    'misissued anonymous registrar cannot enumerate staff message list');
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 1,
    'paired device discovers one due pending ID, not tomorrow schedule');
SELECT ok((SELECT authorized IS TRUE AND approved_text = '오늘 오후 4시에 가상 CT 촬영 예정입니다.'
    FROM api.synthetic_due_hospital_message(
        '00000000-0000-4000-8000-000000000975',
        (SELECT message_id FROM api.synthetic_due_hospital_message_ids(
            '00000000-0000-4000-8000-000000000975') LIMIT 1))),
    'paired device receives exact approved due wording after atomic recheck');
SELECT ok((SELECT authorized IS FALSE AND approved_text IS NULL
    FROM api.synthetic_due_hospital_message(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000999')),
    'future message cannot be fetched by ID');
RESET ROLE;
UPDATE kof5.hospital_message SET due_at = now() - interval '1 minute'
WHERE message_id = '00000000-0000-4000-8000-000000000999';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 2,
    'same approved schedule becomes discoverable only after DB due time');
SELECT ok((SELECT authorized IS TRUE AND approved_text = '내일 가상 검사 예정입니다.'
    FROM api.synthetic_due_hospital_message(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000999')),
    'per-ID recheck offers exact wording after due time');
RESET ROLE;
INSERT INTO kof5.hospital_message
    (patient_id, encounter_id, approved_text, approved_by_staff_ref, approved_at, due_at)
VALUES ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
        '가상 추가 메시지 1', 'TEST-APPROVER', now() - interval '1 minute', now() - interval '1 minute'),
       ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
        '가상 추가 메시지 2', 'TEST-APPROVER', now() - interval '1 minute', now() - interval '1 minute');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 3,
    'device discovery is bounded at three due IDs');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000995', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000995","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 0,
    'unpaired device discovers no due ID');
SELECT ok((SELECT authorized IS FALSE AND approved_text IS NULL
    FROM api.synthetic_due_hospital_message(
        '00000000-0000-4000-8000-000000000975',
        (SELECT message_id FROM kof5.hospital_message WHERE approved_text =
            '오늘 오후 4시에 가상 CT 촬영 예정입니다.' LIMIT 1))),
    'unpaired device receives false/null even with a known ID');
RESET ROLE;

UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000982';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')), 0,
    'ambient consent withdrawal removes due discovery immediately');
SELECT ok((SELECT authorized IS FALSE AND approved_text IS NULL
    FROM api.synthetic_due_hospital_message(
        '00000000-0000-4000-8000-000000000975',
        (SELECT message_id FROM kof5.hospital_message WHERE approved_text =
            '오늘 오후 4시에 가상 CT 촬영 예정입니다.' LIMIT 1))),
    'consent withdrawal denies per-ID wording immediately');

SELECT * FROM finish();
ROLLBACK;
