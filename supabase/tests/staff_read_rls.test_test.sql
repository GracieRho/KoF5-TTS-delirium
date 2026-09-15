BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(15);

-- Transactional, synthetic Auth users. No clinical or real account data.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-000000000001'), -- H1 registrar
    ('00000000-0000-4000-8000-000000000002'), -- H1 assigned staff
    ('00000000-0000-4000-8000-000000000003'), -- H2 registrar
    ('00000000-0000-4000-8000-000000000004'), -- H1 unverified staff
    ('00000000-0000-4000-8000-000000000005'), -- outsider
    ('00000000-0000-4000-8000-000000000006'); -- expired H1 registrar

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000101', 'TEST-H1', 'TEST-P1', '가상 환자 A', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000102', 'TEST-H1', 'TEST-P2', '가상 환자 B', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000103', 'TEST-H2', 'TEST-P3', '가상 환자 C', 'TEST-STAFF');

INSERT INTO kof5.hospital_encounter (
    patient_id, ehr_encounter_ref, status, admitted_at, ward_ref
) VALUES
    ('00000000-0000-4000-8000-000000000101', 'TEST-E1', 'in_progress', now(), 'TEST-WARD-1'),
    ('00000000-0000-4000-8000-000000000102', 'TEST-E2', 'in_progress', now(), 'TEST-WARD-2'),
    ('00000000-0000-4000-8000-000000000103', 'TEST-E3', 'in_progress', now(), 'TEST-WARD-3');

INSERT INTO kof5.hospital_staff_membership (
    membership_id, auth_user_id, hospital_ref, product_role, status,
    effective_at, verified_by_staff_ref, verified_at, revoked_at, expires_at
) VALUES
    ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000001',
     'TEST-H1', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now(), NULL, NULL),
    ('00000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-000000000002',
     'TEST-H1', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now(), NULL, NULL),
    ('00000000-0000-4000-8000-000000000203', '00000000-0000-4000-8000-000000000003',
     'TEST-H2', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now(), NULL, NULL),
    ('00000000-0000-4000-8000-000000000204', '00000000-0000-4000-8000-000000000004',
     'TEST-H1', 'registrar', 'pending', NULL, NULL, NULL, NULL, NULL),
    ('00000000-0000-4000-8000-000000000205', '00000000-0000-4000-8000-000000000006',
     'TEST-H1', 'registrar', 'verified', now() - interval '2 days', 'TEST-VERIFY', now(),
     NULL, now() - interval '1 day');

INSERT INTO kof5.hospital_staff_assignment (
    membership_id, hospital_ref, patient_id, status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES
    ('00000000-0000-4000-8000-000000000202', 'TEST-H1',
     '00000000-0000-4000-8000-000000000101', 'verified',
     now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000202', 'TEST-H1',
     '00000000-0000-4000-8000-000000000102', 'pending', NULL, NULL, NULL);

SELECT ok((SELECT count(*) FROM pg_class
    WHERE relnamespace = 'kof5'::regnamespace
      AND relname IN ('hospital_staff_membership', 'hospital_staff_assignment')
      AND relrowsecurity AND relforcerowsecurity) = 2,
    'new access tables enforce RLS');
SELECT ok(NOT has_schema_privilege('anon', 'api', 'USAGE'),
    'signed-out role has no API schema usage');
SELECT ok(NOT has_table_privilege('anon', 'api.hospital_patient_list', 'SELECT'),
    'signed-out role cannot read hospital view');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.patient_voice_profile', 'SELECT'),
    'staff cannot directly select voice feature metadata');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_patient', 'INSERT'),
    'staff cannot self-register patients before the approval workflow');
SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
    FROM pg_class WHERE oid = 'api.hospital_patient_list'::regclass),
    'hospital view executes with caller RLS');
SELECT throws_ok($sql$
    INSERT INTO kof5.hospital_staff_assignment (
        membership_id, hospital_ref, patient_id, status
    ) VALUES (
        '00000000-0000-4000-8000-000000000202', 'TEST-H1',
        '00000000-0000-4000-8000-000000000103', 'pending'
    )
$sql$, '23503',
    'insert or update on table "hospital_staff_assignment" violates foreign key constraint "hospital_staff_assignment_patient_id_hospital_ref_fkey"',
    'assignment cannot cross hospitals');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 2,
    'verified H1 registrar sees only H1 patients');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 1,
    'assigned H1 staff sees only their verified patient');
SELECT is((SELECT count(*)::integer FROM kof5.hospital_encounter), 1,
    'assigned H1 staff sees only their patient encounter');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 1,
    'verified H2 registrar sees only H2 patient');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 0,
    'pending H1 staff sees no patient');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 0,
    'authenticated outsider sees no patient');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000006', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 0,
    'expired registrar sees no patient');
RESET ROLE;

UPDATE kof5.hospital_staff_membership
SET status = 'revoked', revoked_at = now()
WHERE auth_user_id = '00000000-0000-4000-8000-000000000003';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
SELECT is((SELECT count(*)::integer FROM api.hospital_patient_list), 0,
    'revoked registrar immediately loses patient access');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
