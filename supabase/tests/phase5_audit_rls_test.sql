BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(9);

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity
    FROM pg_class WHERE oid = 'kof5.safety_audit_event'::regclass),
    'safety events force RLS');
SELECT ok(NOT has_table_privilege('anon', 'kof5.safety_audit_event', 'SELECT'),
    'anonymous users cannot read safety events');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.safety_audit_event', 'SELECT'),
    'authenticated users cannot read safety events');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.safety_audit_event', 'INSERT'),
    'authenticated users cannot forge safety events');
SELECT ok(NOT has_table_privilege('service_role', 'kof5.safety_audit_event', 'INSERT'),
    'service role has no direct event grant');
SELECT is((SELECT count(*)::integer FROM information_schema.columns
    WHERE table_schema = 'kof5' AND table_name = 'safety_audit_event'
      AND column_name IN ('transcript', 'audio', 'details', 'free_text')), 0,
    'safety audit has no speech or free-text payload column');

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES (
    '00000000-0000-4000-8000-000000000951', 'TEST-AUDIT', 'TEST-AUDIT-P',
    '가상 환자', 'TEST-STAFF'
);
INSERT INTO kof5.safety_audit_event (patient_id, event_type)
VALUES ('00000000-0000-4000-8000-000000000951', 'patient_dissent');
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id = '00000000-0000-4000-8000-000000000951'), 1,
    'privileged synthetic event can be recorded');
SELECT throws_ok($sql$
    INSERT INTO kof5.safety_audit_event (event_type) VALUES ('speech_transcript')
$sql$, '23514', NULL, 'unlisted payload-like event is rejected');
DELETE FROM kof5.hospital_patient
WHERE patient_id = '00000000-0000-4000-8000-000000000951';
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id IS NULL AND event_type = 'patient_dissent'), 1,
    'patient deletion severs the audit row patient reference');

SELECT * FROM finish();
ROLLBACK;
