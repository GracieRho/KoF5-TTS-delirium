BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT no_plan();

-- All Auth users and patient 975 are synthetic; the transaction rolls back.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false), -- assigned care_staff
    ('00000000-0000-4000-8000-000000000993', false), -- unassigned staff
    ('00000000-0000-4000-8000-000000000994', true),  -- paired device
    ('00000000-0000-4000-8000-000000000995', true); -- unpaired device
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-ALERT-H',
        'TEST-ALERT-P', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-ALERT-E',
        'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at)
VALUES ('TEST-ALERT-H', 'approved', 'TEST-INSTITUTION', 'TEST-CLINICAL',
        now() - interval '1 day');
INSERT INTO kof5.hospital_staff_membership
    (membership_id, auth_user_id, hospital_ref, product_role, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961',
        '00000000-0000-4000-8000-000000000991', 'TEST-ALERT-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962',
        '00000000-0000-4000-8000-000000000994', 'TEST-ALERT-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment
    (membership_id, hospital_ref, patient_id, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-ALERT-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', 'TEST-ALERT-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981',
        '00000000-0000-4000-8000-000000000975', 'patient_participation',
        'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000982',
        '00000000-0000-4000-8000-000000000975', 'ambient_processing',
        'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983',
        '00000000-0000-4000-8000-000000000975', 'patient_voice_feature',
        'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile
    (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
     embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
     enrolled_by_staff_ref, enrolled_at)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983', 'active', 30000,
        'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted',
        'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment
    (device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at)
VALUES ('00000000-0000-4000-8000-000000000994',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000991', now() + interval '2 hours');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
    WHERE oid = 'kof5.synthetic_aux_alert'::regclass), 'alert table force RLS');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.synthetic_aux_alert', 'INSERT'),
    'app roles cannot directly create an alert row');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.synthetic_aux_alert', 'UPDATE'),
    'app roles cannot directly forge state');
SELECT ok(NOT has_table_privilege('anon', 'kof5.synthetic_aux_alert', 'SELECT'),
    'signed-out role cannot read private alerts');
SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_alert_create(uuid,text,uuid)', 'EXECUTE'),
    'signed-out role cannot call device create');
SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_alert_ack(uuid)', 'EXECUTE'),
    'signed-out role cannot ACK');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.synthetic_alert_create(uuid,text,uuid)'::regprocedure),
    'exposed device RPC is invoker');
SELECT is((SELECT count(*)::integer FROM information_schema.columns
    WHERE table_schema = 'kof5' AND table_name = 'synthetic_aux_alert'
      AND column_name IN ('transcript', 'audio', 'free_text', 'details')), 0,
    'alert stores no speech or free-text payload');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT ready IS FALSE AND patient_id IS NULL
    FROM api.synthetic_alert_staff_ready()), 'anonymous device cannot be staff');
SELECT is((SELECT count(*)::integer FROM api.synthetic_alert_staff_list()), 0,
    'misissued anonymous staff membership cannot read alerts');
SELECT ok((SELECT authorized IS FALSE AND alert_id IS NULL
    FROM api.synthetic_alert_ack('00000000-0000-4000-8000-000000000800')),
    'anonymous device cannot ACK even with misissued staff assignment');
SELECT ok((SELECT authorized AND state = 'created' AND alert_id IS NOT NULL
    FROM api.synthetic_alert_create(
        '00000000-0000-4000-8000-000000000975', 'breathing',
        '00000000-0000-4000-8000-000000000801')),
    'paired anonymous device creates one synthetic alert');
RESET ROLE;
SELECT set_config('test.alert_one',
    (SELECT alert_id::text FROM kof5.synthetic_aux_alert
     WHERE idempotency_key = '00000000-0000-4000-8000-000000000801'), true);
SELECT is((SELECT count(*)::integer FROM kof5.synthetic_aux_alert), 1,
    'one bounded alert row exists');
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'
      AND event_type IN ('high_risk_utterance_detected', 'alert_created')), 2,
    'created alert records payload-free detected and created audit events');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized AND alert_id = current_setting('test.alert_one')::uuid
    FROM api.synthetic_alert_create(
        '00000000-0000-4000-8000-000000000975', 'breathing',
        '00000000-0000-4000-8000-000000000801')),
    'same idempotency key returns same alert');
SELECT ok((SELECT authorized IS FALSE AND alert_id IS NULL
    FROM api.synthetic_alert_create(
        '00000000-0000-4000-8000-000000000975', 'fall',
        '00000000-0000-4000-8000-000000000801')),
    'same key cannot change risk category');
SELECT ok((SELECT authorized IS FALSE AND alert_id IS NULL
    FROM api.synthetic_alert_create(
        '00000000-0000-4000-8000-000000000975', 'fall',
        '00000000-0000-4000-8000-000000000802')),
    'new alert is device-rate-limited for 30 seconds');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000975', 'patient said free text',
    '00000000-0000-4000-8000-000000000803')),
    'unbounded risk category is rejected');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000977', 'breathing',
    '00000000-0000-4000-8000-000000000804')),
    'non-fixture patient cannot create alert');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000995', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000995","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000975', 'breathing',
    '00000000-0000-4000-8000-000000000805')),
    'unpaired anonymous device cannot create alert');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND patient_id =
    '00000000-0000-4000-8000-000000000975'::uuid
    FROM api.synthetic_alert_staff_ready()), 'assigned permanent care_staff is ready');
SELECT is((SELECT count(*)::integer FROM api.synthetic_alert_staff_list()), 1,
    'staff sees one created alert before any dashboard receipt');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_ack(
    current_setting('test.alert_one')::uuid)), 'HTTP call cannot ACK a merely created row');
SELECT ok((SELECT authorized AND state = 'delivered' FROM
    api.synthetic_alert_dashboard_receipt(current_setting('test.alert_one')::uuid)),
    'explicit dashboard receipt records delivered, not ACK');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_dashboard_receipt(
    current_setting('test.alert_one')::uuid)), 'duplicate receipt cannot advance');
SELECT ok((SELECT authorized AND state = 'acknowledged' FROM
    api.synthetic_alert_ack(current_setting('test.alert_one')::uuid)),
    'assigned staff explicit ACK advances delivered row');
SELECT ok((SELECT authorized AND state = 'resolved' FROM
    api.synthetic_alert_resolve(current_setting('test.alert_one')::uuid)),
    'assigned staff explicit resolve follows ACK');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_resolve(
    current_setting('test.alert_one')::uuid)), 'duplicate resolve cannot advance');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'
      AND event_type IN ('alert_delivered', 'alert_acknowledged', 'alert_resolved')), 3,
    'delivered, ACK and resolved have distinct payload-free audit events');

-- Move old rows back in synthetic time to exercise both failure paths without sleep.
UPDATE kof5.synthetic_aux_alert SET created_at = now() - interval '2 minutes'
WHERE alert_id = current_setting('test.alert_one')::uuid;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized AND state = 'created' FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000975', 'fall',
    '00000000-0000-4000-8000-000000000806')),
    'second alert can be created after rate window');
RESET ROLE;
SELECT set_config('test.alert_two',
    (SELECT alert_id::text FROM kof5.synthetic_aux_alert
     WHERE idempotency_key = '00000000-0000-4000-8000-000000000806'), true);
UPDATE kof5.synthetic_aux_alert SET created_at = now() - interval '2 minutes'
WHERE alert_id = current_setting('test.alert_two')::uuid;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT state = 'created' FROM api.synthetic_alert_staff_list()
    WHERE alert_id = current_setting('test.alert_two')::uuid),
    'read-only staff list does not silently mark a timeout');
SELECT ok((SELECT authorized AND failed_count = 1
    FROM api.synthetic_alert_timeout_sweep()),
    'explicit synthetic sweep records created-to-delivery-timeout failure');
SELECT ok((SELECT state = 'failed' AND failure_reason = 'delivery_timeout'
    AND failed_at IS NOT NULL AND delivered_at IS NULL
    FROM api.synthetic_alert_staff_list()
    WHERE alert_id = current_setting('test.alert_two')::uuid),
    'failure is visible without claiming delivery or ACK');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_ack(
    current_setting('test.alert_two')::uuid)),
    'failed created alert cannot be ACKed');
RESET ROLE;
UPDATE kof5.synthetic_aux_alert SET created_at = now() - interval '2 minutes'
WHERE alert_id = current_setting('test.alert_two')::uuid;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000975', 'pain',
    '00000000-0000-4000-8000-000000000807')),
    'third alert exercises ACK timeout');
RESET ROLE;
SELECT set_config('test.alert_three',
    (SELECT alert_id::text FROM kof5.synthetic_aux_alert
     WHERE idempotency_key = '00000000-0000-4000-8000-000000000807'), true);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT authorized AND state = 'delivered' FROM
    api.synthetic_alert_dashboard_receipt(current_setting('test.alert_three')::uuid)),
    'third alert has staff portal receipt, not ACK');
RESET ROLE;
UPDATE kof5.synthetic_aux_alert SET delivered_at = now() - interval '6 minutes'
WHERE alert_id = current_setting('test.alert_three')::uuid;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT authorized AND failed_count = 1 FROM
    api.synthetic_alert_timeout_sweep()),
    'delivered row without ACK reaches separate ACK timeout failure');
SELECT ok((SELECT state = 'failed' AND failure_reason = 'ack_timeout'
    AND delivered_at IS NOT NULL AND acknowledged_at IS NULL
    FROM api.synthetic_alert_staff_list()
    WHERE alert_id = current_setting('test.alert_three')::uuid),
    'ACK timeout retains portal receipt but not staff confirmation');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_ack(
    current_setting('test.alert_three')::uuid)),
    'late ACK cannot bypass timeout');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'
      AND event_type = 'alert_failed'), 2,
    'each failure creates one bounded audit event');

UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000982';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_create(
    '00000000-0000-4000-8000-000000000975', 'distress',
    '00000000-0000-4000-8000-000000000808')),
    'ambient consent withdrawal stops fresh device alert creation');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_alert_staff_list()), 3,
    'assigned staff can review historical alerts after device consent withdrawal');
RESET ROLE;
UPDATE kof5.hospital_staff_assignment SET status = 'revoked', revoked_at = now()
WHERE membership_id = '00000000-0000-4000-8000-000000000961';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE FROM api.synthetic_alert_staff_ready()),
    'revoked staff assignment removes alert readiness');
SELECT is((SELECT count(*)::integer FROM api.synthetic_alert_staff_list()), 0,
    'revoked staff cannot read historical alerts');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_timeout_sweep()),
    'revoked staff cannot sweep timeouts');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_alert_ack(
    current_setting('test.alert_one')::uuid)),
    'revoked staff cannot mutate alerts');

SELECT * FROM finish();
ROLLBACK;
