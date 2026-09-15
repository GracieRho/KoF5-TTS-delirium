BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(15);

SELECT ok((SELECT reloptions @> ARRAY['security_invoker=true']
    FROM pg_class WHERE oid = 'kof5.usable_patient_voice_profile'::regclass),
    'private voice view applies caller RLS');
SELECT ok(NOT has_table_privilege('anon', 'kof5.usable_patient_voice_profile', 'SELECT'),
    'anonymous users cannot read usable voice metadata');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.usable_patient_voice_profile', 'SELECT'),
    'authenticated users cannot read usable voice metadata');
SELECT ok(NOT has_table_privilege('service_role', 'kof5.usable_patient_voice_profile', 'SELECT'),
    'service role has no direct voice-view grant');

INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES (
    '00000000-0000-4000-8000-000000000961', 'TEST-VOICE', 'TEST-VOICE-P',
    '가상 환자', 'TEST-STAFF'
);
INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status, admitted_at
) VALUES (
    '00000000-0000-4000-8000-000000000962',
    '00000000-0000-4000-8000-000000000961', 'TEST-VOICE-E',
    'in_progress', now() - interval '1 day'
);
INSERT INTO kof5.consent_record (
    consent_id, patient_id, scope, signer_role, signer_ref, assent_status,
    status, effective_at, recorded_by_staff_ref
) VALUES (
    '00000000-0000-4000-8000-000000000963',
    '00000000-0000-4000-8000-000000000961',
    'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented',
    'active', now() - interval '1 day', 'TEST-STAFF'
);
INSERT INTO kof5.patient_voice_profile (
    profile_id, patient_id, encounter_id, consent_id, status, quality_status,
    enrollment_duration_ms, embedding_model, embedding_version,
    encrypted_embedding_ref, enrolled_at, enrolled_by_staff_ref
) VALUES (
    '00000000-0000-4000-8000-000000000964',
    '00000000-0000-4000-8000-000000000961',
    '00000000-0000-4000-8000-000000000962',
    '00000000-0000-4000-8000-000000000963',
    'active', 'accepted', 30000, 'TEST-MODEL', 'TEST-VERSION',
    'encrypted-test-ref', now(), 'TEST-STAFF'
);

SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 1,
    'active profile with current assent, consent and encounter is eligible');

UPDATE kof5.consent_record SET assent_status = 'not_attempted'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'unattempted assent blocks use despite active consent status');
UPDATE kof5.consent_record SET assent_status = 'assented'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';

UPDATE kof5.consent_record SET expires_at = now() - interval '1 hour'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'past expiry blocks use despite active consent status');
UPDATE kof5.consent_record SET expires_at = NULL
WHERE consent_id = '00000000-0000-4000-8000-000000000963';

UPDATE kof5.consent_record SET effective_at = now() + interval '1 day'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'future consent effective time blocks use');
UPDATE kof5.consent_record SET effective_at = now() - interval '1 day'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';

UPDATE kof5.consent_record SET signer_role = 'guardian'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'guardian signer alone cannot authorize patient voice feature');
UPDATE kof5.consent_record SET signer_role = 'patient'
WHERE consent_id = '00000000-0000-4000-8000-000000000963';

UPDATE kof5.hospital_encounter SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000962';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'finished admission blocks use of earlier voice profile');
UPDATE kof5.hospital_encounter SET status = 'in_progress', discharged_at = NULL
WHERE encounter_id = '00000000-0000-4000-8000-000000000962';

UPDATE kof5.hospital_patient SET active = false
WHERE patient_id = '00000000-0000-4000-8000-000000000961';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'inactive patient blocks use');
UPDATE kof5.hospital_patient SET active = true
WHERE patient_id = '00000000-0000-4000-8000-000000000961';

UPDATE kof5.patient_voice_profile SET status = 'revoked', revoked_at = now()
WHERE profile_id = '00000000-0000-4000-8000-000000000964';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'revoked profile blocks use');
UPDATE kof5.patient_voice_profile SET status = 'active', revoked_at = NULL
WHERE profile_id = '00000000-0000-4000-8000-000000000964';

UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000963';
SELECT is((SELECT count(*)::integer FROM kof5.usable_patient_voice_profile), 0,
    'withdrawal immediately blocks prior active profile');
SELECT is((SELECT status FROM kof5.patient_voice_profile
    WHERE profile_id = '00000000-0000-4000-8000-000000000964'), 'active',
    'eligibility withdrawal does not falsely mark external voice object deleted');
SELECT throws_ok($sql$
    UPDATE kof5.consent_record SET status = 'active', withdrawn_at = NULL
    WHERE consent_id = '00000000-0000-4000-8000-000000000963'
$sql$, '23514', NULL, 'withdrawn record cannot be reopened to reuse an old profile');

SELECT * FROM finish();
ROLLBACK;
