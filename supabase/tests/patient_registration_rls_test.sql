BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(29);

-- Synthetic Auth identities and approvals are rolled back with this transaction.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-000000000711'), -- TEST-H1 registrar
    ('00000000-0000-4000-8000-000000000712'), -- TEST-H2 registrar
    ('00000000-0000-4000-8000-000000000713'), -- TEST-H1 care staff
    ('00000000-0000-4000-8000-000000000714'), -- TEST-H1 pending
    ('00000000-0000-4000-8000-000000000715'), -- TEST-H1 expired
    ('00000000-0000-4000-8000-000000000716'), -- TEST-H1 revoked
    ('00000000-0000-4000-8000-000000000717'); -- outsider

INSERT INTO kof5.hospital_staff_membership (
    auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_at, verified_by_staff_ref, expires_at, revoked_at
) VALUES
    ('00000000-0000-4000-8000-000000000711', 'TEST-H1', 'registrar', 'verified', now() - interval '1 day', now(), 'TEST-VERIFY', NULL, NULL),
    ('00000000-0000-4000-8000-000000000712', 'TEST-H2', 'registrar', 'verified', now() - interval '1 day', now(), 'TEST-VERIFY', NULL, NULL),
    ('00000000-0000-4000-8000-000000000713', 'TEST-H1', 'care_staff', 'verified', now() - interval '1 day', now(), 'TEST-VERIFY', NULL, NULL),
    ('00000000-0000-4000-8000-000000000714', 'TEST-H1', 'registrar', 'pending', NULL, NULL, NULL, NULL, NULL),
    ('00000000-0000-4000-8000-000000000715', 'TEST-H1', 'registrar', 'verified', now() - interval '2 days', now(), 'TEST-VERIFY', now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000000716', 'TEST-H1', 'registrar', 'revoked', NULL, NULL, NULL, NULL, now());

SELECT is((SELECT count(*)::integer FROM kof5.hospital_registry_activation), 0,
    'institution approval gate defaults to no active hospital');
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity
    FROM pg_class WHERE oid = 'kof5.hospital_registry_activation'::regclass),
    'server approval gate enforces RLS');
SELECT ok(NOT has_table_privilege('anon', 'api.hospital_patient_registration', 'INSERT'),
    'signed-out role cannot access registration Data API view');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_registry_activation', 'INSERT'),
    'signed-in staff cannot forge the approval gate');
SELECT ok(NOT has_column_privilege('authenticated', 'kof5.hospital_patient', 'registered_by_staff_ref', 'INSERT'),
    'signed-in staff cannot submit a spoofed registrar reference');
SELECT ok(NOT has_table_privilege('authenticated', 'api.hospital_patient_registration', 'UPDATE'),
    'registration view does not allow patient edits');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
    FROM pg_class WHERE oid = 'api.hospital_patient_registration'::regclass),
    'registration view uses caller privileges and RLS');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
    FROM pg_class WHERE oid = 'api.hospital_registration_ready'::regclass),
    'readiness view uses caller privileges and RLS');
SELECT ok(NOT has_table_privilege('anon', 'api.hospital_registration_ready', 'SELECT'),
    'signed-out role cannot query registrar readiness');
SELECT is((SELECT string_agg(column_name, ',' ORDER BY ordinal_position)
    FROM information_schema.columns
    WHERE table_schema = 'api' AND table_name = 'hospital_registration_ready'),
    'hospital_ref,ready', 'readiness view does not reveal private approval references');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000711', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 1,
    'current registrar sees only their own hospital readiness');
SELECT is((SELECT ready FROM api.hospital_registration_ready), false,
    'registration readiness is false while approval gate has no row');
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P711-BLOCKED', '가상 환자')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000713', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 0,
    'care staff receives no registrar readiness row');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000714', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 0,
    'pending registrar receives no readiness row');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000715', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 0,
    'expired registrar receives no readiness row');
RESET ROLE;

-- Only the trusted database admin can record a synthetic approval for a test hospital.
INSERT INTO kof5.hospital_registry_activation (
    hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at
) VALUES ('TEST-H1', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY', now() - interval '1 day');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000711', true);
SELECT is((SELECT ready FROM api.hospital_registration_ready), true,
    'synthetic server approval switches current registrar readiness on');
SELECT lives_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P711', '가상 환자')
$sql$, 'approved current registrar can register a synthetic patient');
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P711', '중복 가상 환자')
$sql$, '23505');
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H2', 'TEST-P712-CROSS', '다른 기관 가상 환자')
$sql$, '42501');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000713', true);
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P713', '간병 직원 가상 환자')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000714', true);
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P714', '대기 직원 가상 환자')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000715', true);
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P715', '만료 직원 가상 환자')
$sql$, '42501');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000716', true);
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P716', '철회 직원 가상 환자')
$sql$, '42501');
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 0,
    'revoked registrar receives no readiness row');
RESET ROLE;

SELECT is((SELECT registered_by_staff_ref FROM kof5.hospital_patient
    WHERE hospital_ref = 'TEST-H1' AND ehr_patient_ref = 'TEST-P711'),
    '00000000-0000-4000-8000-000000000711',
    'registration stores the authenticated registrar ID rather than client text');

UPDATE kof5.hospital_registry_activation
SET status = 'revoked', revoked_at = now() WHERE hospital_ref = 'TEST-H1';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000711', true);
SELECT is((SELECT ready FROM api.hospital_registration_ready), false,
    'approval gate revocation immediately switches readiness off');
SELECT throws_ok($sql$
    INSERT INTO api.hospital_patient_registration
        (hospital_ref, ehr_patient_ref, staff_display_name)
    VALUES ('TEST-H1', 'TEST-P711-AFTER', '승인 철회 뒤 가상 환자')
$sql$, '42501');
RESET ROLE;

UPDATE kof5.hospital_staff_membership
SET status = 'revoked', revoked_at = now()
WHERE auth_user_id = '00000000-0000-4000-8000-000000000711';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000711', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_registration_ready), 0,
    'registrar membership revocation hides readiness altogether');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
