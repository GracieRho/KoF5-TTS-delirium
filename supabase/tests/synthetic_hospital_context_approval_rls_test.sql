BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(36);

-- Fixed, throwaway synthetic fixture. All rows roll back below.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false),
    ('00000000-0000-4000-8000-000000000992', false),
    ('00000000-0000-4000-8000-000000000993', false),
    ('00000000-0000-4000-8000-000000000994', true),
    ('00000000-0000-4000-8000-000000000995', false);
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name,
     registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-CONTEXT-H',
        'TEST-P975', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-E975',
        'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref,
     clinical_safety_approval_ref, approved_at)
VALUES ('TEST-CONTEXT-H', 'approved', 'TEST-INSTITUTION',
        'TEST-SAFETY', now() - interval '1 day');
INSERT INTO kof5.hospital_staff_membership
    (membership_id, auth_user_id, hospital_ref, product_role, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961',
        '00000000-0000-4000-8000-000000000991', 'TEST-CONTEXT-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962',
        '00000000-0000-4000-8000-000000000992', 'TEST-CONTEXT-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000963',
        '00000000-0000-4000-8000-000000000994', 'TEST-CONTEXT-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment
    (membership_id, hospital_ref, patient_id, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-CONTEXT-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', 'TEST-CONTEXT-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000963', 'TEST-CONTEXT-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981',
        '00000000-0000-4000-8000-000000000975', 'patient_participation',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000982',
        '00000000-0000-4000-8000-000000000975', 'ambient_processing',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983',
        '00000000-0000-4000-8000-000000000975', 'patient_voice_feature',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile
    (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
     embedding_model, embedding_version, encrypted_embedding_ref,
     quality_status, enrolled_by_staff_ref, enrolled_at)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983', 'active', 30000,
        'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted',
        'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment
    (device_user_id, patient_id, encounter_id, paired_by_staff_user_id,
     expires_at)
VALUES ('00000000-0000-4000-8000-000000000994',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000991',
        now() + interval '2 hours');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
    WHERE oid = 'kof5.synthetic_hospital_context_draft'::regclass),
    'synthetic draft is FORCE RLS');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true'] FROM pg_class
    WHERE oid = 'api.synthetic_hospital_context_draft'::regclass),
    'exposed draft view obeys caller RLS');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true'] FROM pg_class
    WHERE oid = 'api.hospital_context_current'::regclass),
    'existing hospital facts view remains invoker after source addition');
SELECT ok(NOT has_table_privilege('anon', 'api.synthetic_hospital_context_draft', 'INSERT'),
    'signed-out role cannot propose');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_context_fact', 'INSERT'),
    'authenticated staff cannot insert approved facts directly');
SELECT ok(NOT has_column_privilege('authenticated',
    'api.synthetic_hospital_context_draft', 'approved_at', 'UPDATE'),
    'client cannot spoof approval time');
SELECT ok(NOT has_column_privilege('authenticated',
    'api.synthetic_hospital_context_draft', 'proposed_by_auth_user_id', 'INSERT'),
    'client cannot spoof proposer');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000993', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000993","is_anonymous":false}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 307호입니다.', 'TEST-ROOM-307')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 익명 307호입니다.', 'TEST-ROOM-307')
$sql$, '42501');
SELECT is((SELECT count(*)::integer FROM api.synthetic_hospital_context_draft), 0,
    'anonymous device cannot enumerate hospital staff drafts');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000995', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000995","is_anonymous":false}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 보호자 307호입니다.', 'TEST-ROOM-307')
$sql$, '42501');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000977',
            '00000000-0000-4000-8000-000000000978', 'room',
            '실제 환자 쓰기 금지', 'TEST-ROOM-307')
$sql$, '42501');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'medication',
            '가상 약 처방입니다.', 'TEST-ROOM-307')
$sql$, '23514');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '약을 드셔도 괜찮습니다.', 'TEST-ROOM-307')
$sql$, '23514');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 307호입니다.', 'EHR-REAL-PATIENT-REF')
$sql$, '23514');
SELECT lives_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 307호입니다.', 'TEST-ROOM-307')
$sql$, 'assigned staff can propose an exact safe synthetic fact');
SELECT is((SELECT count(*)::integer FROM api.synthetic_hospital_context_draft), 1,
    'proposer reads own synthetic draft');
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 0,
    'unapproved text does not enter the existing staff read view');
WITH self_approval AS (
    UPDATE api.synthetic_hospital_context_draft SET status = 'approved'
    WHERE proposed_text = '가상 307호입니다.' RETURNING draft_id
) SELECT is((SELECT count(*)::integer FROM self_approval), 0,
    'proposer cannot self-approve');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '제 병실은 어디인가요?')),
    'paired device receives no unapproved context');

SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000992', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000992","is_anonymous":false}', true);
SELECT lives_ok($sql$UPDATE api.synthetic_hospital_context_draft
    SET status = 'approved' WHERE proposed_text = '가상 307호입니다.'
$sql$, 'distinct assigned staff can approve exact context');
SELECT is((SELECT count(*)::integer FROM api.synthetic_hospital_context_draft
    WHERE status = 'approved'), 1, 'approval state is recorded');
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 1,
    'approved fact appears in existing staff current view');
SELECT is((SELECT synthetic_source_ref FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'),
    'TEST-ROOM-307', 'approved assigned staff can inspect exact synthetic source');
RESET ROLE;
SELECT ok((SELECT f.fact_id = d.draft_id AND f.content = d.proposed_text
           AND f.category = d.category AND f.synthetic_source_ref = d.source_ref
    FROM kof5.hospital_context_fact f
    JOIN kof5.synthetic_hospital_context_draft d ON d.draft_id = f.fact_id),
    'published fact retains exact text, category, source and draft UUID');
SELECT ok((SELECT f.source_staff_ref = d.proposed_by_auth_user_id::text
           AND f.approved_by_staff_ref = d.approved_by_auth_user_id::text
           AND f.verified_at = d.approved_at
           AND f.valid_until = d.approved_at + interval '24 hours'
    FROM kof5.hospital_context_fact f
    JOIN kof5.synthetic_hospital_context_draft d ON d.draft_id = f.fact_id),
    'Auth attribution and synthetic 24h validity come from DB');
SELECT throws_ok($sql$UPDATE kof5.synthetic_hospital_context_draft
    SET source_ref = 'TEST-CHANGED'
    WHERE source_ref = 'TEST-ROOM-307'
$sql$, '23514');
SELECT throws_ok($sql$UPDATE kof5.hospital_context_fact
    SET content = '바뀐 원문' WHERE synthetic_source_ref = 'TEST-ROOM-307'
$sql$, '23514');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE synthetic_source_ref IS NOT NULL), 0,
    'paired anonymous device cannot read staff source through the broad view');
SELECT ok((SELECT authorized IS TRUE AND jsonb_array_length(facts) = 1
           AND facts->0->>'content' = '가상 307호입니다.'
           AND NOT (facts->0 ? 'synthetic_source_ref')
    FROM api.patient_hospital_turn_context(
        '00000000-0000-4000-8000-000000000975', '제 병실은 어디인가요?')),
    'paired device sees exact approved room fact but no source through bounded turn RPC');
RESET ROLE;

UPDATE kof5.hospital_staff_assignment SET status = 'revoked', revoked_at = now()
WHERE membership_id = '00000000-0000-4000-8000-000000000962';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000992', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000992","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_hospital_context_draft), 0,
    'revoked assignment cannot list draft or approved origin');
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 0,
    'revoked staff cannot read approved fixture fact');
RESET ROLE;
SAVEPOINT activation_test;
UPDATE kof5.hospital_registry_activation SET status = 'revoked', revoked_at = now()
WHERE hospital_ref = 'TEST-CONTEXT-H';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 0,
    'institution approval loss closes approved staff fixture read');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 308호입니다.', 'TEST-ROOM-308')
$sql$, '42501');
RESET ROLE;
ROLLBACK TO SAVEPOINT activation_test;
UPDATE kof5.hospital_encounter SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_context_current
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 0,
    'ended admission removes approved fixture fact from staff view');
SELECT throws_ok($sql$INSERT INTO api.synthetic_hospital_context_draft
    (patient_id, encounter_id, category, proposed_text, source_ref)
    VALUES ('00000000-0000-4000-8000-000000000975',
            '00000000-0000-4000-8000-000000000976', 'room',
            '가상 종료 후 방입니다.', 'TEST-ROOM-CLOSED')
$sql$, '42501');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
