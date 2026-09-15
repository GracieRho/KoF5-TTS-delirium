BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(17);

-- Synthetic users/registry rows are rolled back. No real family or patient data.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-000000000301'), -- verified guardian
    ('00000000-0000-4000-8000-000000000302'), -- pending guardian
    ('00000000-0000-4000-8000-000000000303'); -- outsider

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000401', 'TEST-H1', 'TEST-GP1', '가상 환자 A', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000402', 'TEST-H1', 'TEST-GP2', '가상 환자 B', 'TEST-STAFF');

INSERT INTO kof5.patient_guardian_link (
    patient_id, guardian_user_id, relationship, access_status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES
    ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-000000000301',
     '딸', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000402', '00000000-0000-4000-8000-000000000302',
     '아들', 'pending', NULL, NULL, NULL);

SELECT ok((SELECT count(*) FROM pg_class
    WHERE relnamespace = 'kof5'::regnamespace
      AND relname IN ('patient_guardian_link', 'family_fact')
      AND relrowsecurity AND relforcerowsecurity) = 2,
    'guardian and memory tables enforce RLS');
SELECT ok(NOT has_table_privilege('anon', 'api.family_context', 'SELECT'),
    'anonymous clients cannot read family facts');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.patient_guardian_link', 'INSERT'),
    'guardians cannot self-verify a patient link');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
    FROM pg_class WHERE oid = 'api.family_context'::regclass),
    'family view executes with caller RLS');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000301', true);
SELECT is((SELECT count(*)::integer FROM api.guardian_links), 1,
    'verified guardian sees only their link');
SELECT is((SELECT count(*)::integer FROM kof5.hospital_patient), 0,
    'guardian cannot read patient identifiers or demographics');
SELECT throws_ok($sql$
    INSERT INTO api.family_context (
        patient_id, author_guardian_user_id, category, content
    ) VALUES (
        '00000000-0000-4000-8000-000000000402',
        '00000000-0000-4000-8000-000000000302', 'family', '가상 다른 보호자 기억'
    )
$sql$, '42501', 'new row violates row-level security policy for table "family_fact"',
    'guardian cannot write another guardian patient fact');
SELECT lives_ok($sql$
    INSERT INTO api.family_context (
        patient_id, author_guardian_user_id, category, content
    ) VALUES (
        '00000000-0000-4000-8000-000000000401',
        '00000000-0000-4000-8000-000000000301', 'travel', '가상 여행 기억'
    )
$sql$, 'verified guardian may write their own family fact');
SELECT is((SELECT count(*)::integer FROM api.family_context), 1,
    'verified guardian reads their own fact');
SELECT lives_ok($sql$
    UPDATE api.family_context SET content = '가상 여행 기억 수정'
    WHERE patient_id = '00000000-0000-4000-8000-000000000401'
$sql$, 'verified guardian may edit their own fact');
SELECT is((SELECT content FROM api.family_context LIMIT 1), '가상 여행 기억 수정',
    'guardian edit changes only the owned fact');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000302', true);
SELECT is((SELECT count(*)::integer FROM api.family_context), 0,
    'pending guardian cannot read family facts');
SELECT throws_ok($sql$
    INSERT INTO api.family_context (
        patient_id, author_guardian_user_id, category, content
    ) VALUES (
        '00000000-0000-4000-8000-000000000402',
        '00000000-0000-4000-8000-000000000302', 'family', '가상 가족 기억'
    )
$sql$, '42501', 'new row violates row-level security policy for table "family_fact"',
    'pending guardian cannot write family facts');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000303', true);
SELECT is((SELECT count(*)::integer FROM api.family_context), 0,
    'authenticated outsider cannot read family facts');
RESET ROLE;

UPDATE kof5.patient_guardian_link
SET access_status = 'revoked', revoked_at = now()
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000301';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000301', true);
SELECT is((SELECT count(*)::integer FROM api.family_context), 0,
    'revoked guardian immediately loses family facts');
SELECT throws_ok($sql$
    INSERT INTO api.family_context (
        patient_id, author_guardian_user_id, category, content
    ) VALUES (
        '00000000-0000-4000-8000-000000000401',
        '00000000-0000-4000-8000-000000000301', 'family', '철회 후 작성'
    )
$sql$, '42501', 'new row violates row-level security policy for table "family_fact"',
    'revoked guardian cannot add a family fact');
RESET ROLE;

UPDATE kof5.patient_guardian_link
SET access_status = 'verified', revoked_at = NULL, expires_at = now() - interval '1 hour'
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000301';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000301', true);
SELECT is((SELECT count(*)::integer FROM api.family_context), 0,
    'expired guardian link cannot read family facts');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
