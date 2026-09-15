-- Run only against a disposable local PostgreSQL database after the registry migration.
-- Synthetic identifiers and references only; the transaction leaves no test rows or roles.
BEGIN;

DO $$
DECLARE
    first_patient uuid;
    second_patient uuid;
    first_encounter uuid;
    second_consent uuid;
    voice_consent uuid;
    active_profile uuid;
BEGIN
    INSERT INTO kof5.hospital_patient (
        hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
    ) VALUES ('synthetic_hospital', 'TEST-001', '가상 환자 A', 'synthetic_staff')
    RETURNING patient_id INTO first_patient;
    INSERT INTO kof5.hospital_patient (
        hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
    ) VALUES ('synthetic_hospital', 'TEST-002', '가상 환자 B', 'synthetic_staff')
    RETURNING patient_id INTO second_patient;

    INSERT INTO kof5.hospital_encounter (
        patient_id, ehr_encounter_ref, status, admitted_at
    ) VALUES (first_patient, 'TEST-ENCOUNTER-001', 'in_progress', now())
    RETURNING encounter_id INTO first_encounter;
    BEGIN
        INSERT INTO kof5.hospital_encounter (
            patient_id, ehr_encounter_ref, status, admitted_at
        ) VALUES (first_patient, 'TEST-ENCOUNTER-002', 'in_progress', now());
        RAISE EXCEPTION 'second current encounter was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO kof5.hospital_encounter (
            patient_id, ehr_encounter_ref, status, admitted_at
        ) VALUES (first_patient, 'TEST-ENCOUNTER-FINISHED', 'finished', now());
        RAISE EXCEPTION 'finished encounter without discharge was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO kof5.consent_record (
        patient_id, scope, signer_role, signer_ref, assent_status, status,
        effective_at, recorded_by_staff_ref
    ) VALUES (
        first_patient, 'patient_voice_feature', 'patient', 'synthetic_patient',
        'assented', 'active', now(), 'synthetic_staff'
    ) RETURNING consent_id INTO voice_consent;
    INSERT INTO kof5.consent_record (
        patient_id, scope, signer_role, signer_ref, assent_status, status,
        effective_at, recorded_by_staff_ref
    ) VALUES (
        second_patient, 'patient_voice_feature', 'patient', 'synthetic_patient',
        'assented', 'active', now(), 'synthetic_staff'
    ) RETURNING consent_id INTO second_consent;
    BEGIN
        INSERT INTO kof5.consent_record (
            patient_id, scope, signer_role, signer_ref, assent_status, status,
            effective_at, recorded_by_staff_ref
        ) VALUES (
            first_patient, 'patient_participation', 'patient', 'synthetic_patient',
            'declined', 'active', now(), 'synthetic_staff'
        );
        RAISE EXCEPTION 'active consent despite patient refusal was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO kof5.patient_voice_profile (
            patient_id, encounter_id, consent_id, status, quality_status,
            enrolled_by_staff_ref
        ) VALUES (first_patient, first_encounter, second_consent, 'pending', 'pending', 'synthetic_staff');
        RAISE EXCEPTION 'cross-patient consent was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO kof5.patient_voice_profile (
            patient_id, encounter_id, consent_id, status, quality_status,
            enrollment_duration_ms, embedding_model, embedding_version,
            enrolled_at, enrolled_by_staff_ref
        ) VALUES (
            first_patient, first_encounter, voice_consent, 'active', 'accepted',
            30000, 'synthetic_model', 'test', now(), 'synthetic_staff'
        );
        RAISE EXCEPTION 'active profile without encrypted embedding was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO kof5.patient_voice_profile (
        patient_id, encounter_id, consent_id, status, quality_status,
        enrollment_duration_ms, embedding_model, embedding_version,
        encrypted_embedding_ref, enrolled_at, enrolled_by_staff_ref
    ) VALUES (
        first_patient, first_encounter, voice_consent, 'active', 'accepted',
        30000, 'synthetic_model', 'test', 'encrypted-test-ref', now(), 'synthetic_staff'
    ) RETURNING profile_id INTO active_profile;
    BEGIN
        INSERT INTO kof5.patient_voice_profile (
            patient_id, encounter_id, consent_id, status, quality_status,
            enrollment_duration_ms, embedding_model, embedding_version,
            encrypted_embedding_ref, enrolled_at, enrolled_by_staff_ref
        ) VALUES (
            first_patient, first_encounter, voice_consent, 'active', 'accepted',
            30000, 'synthetic_model', 'test', 'encrypted-test-ref-2', now(), 'synthetic_staff'
        );
        RAISE EXCEPTION 'second active voice profile was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO kof5.patient_voice_sample (
            profile_id, temporary_encrypted_object_ref, codec, duration_ms,
            captured_at, purge_due_at, purged_at
        ) VALUES (
            active_profile, 'raw-test-ref', 'pcm16_wav', 30000,
            now(), now() + interval '1 minute', now()
        );
        RAISE EXCEPTION 'purged sample still referencing audio was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO kof5.patient_voice_sample (
        profile_id, codec, duration_ms, captured_at, purge_due_at, purged_at
    ) VALUES (
        active_profile, 'pcm16_wav', 30000,
        now(), now() + interval '1 minute', now()
    );

    IF EXISTS (SELECT 1 FROM pg_class
        WHERE relnamespace = 'kof5'::regnamespace AND relkind = 'r'
        AND NOT (relrowsecurity AND relforcerowsecurity)) THEN
        RAISE EXCEPTION 'registry tables are not all FORCE RLS';
    END IF;
END $$;

CREATE ROLE kof5_registry_smoke_reader;
-- Supabase's local postgres role can create roles but is not a superuser.
GRANT kof5_registry_smoke_reader TO postgres WITH SET TRUE;
GRANT USAGE ON SCHEMA kof5 TO kof5_registry_smoke_reader;
GRANT SELECT ON kof5.hospital_patient TO kof5_registry_smoke_reader;
SET ROLE kof5_registry_smoke_reader;
DO $$
BEGIN
    IF (SELECT count(*) FROM kof5.hospital_patient) <> 0 THEN
        RAISE EXCEPTION 'non-privileged role can read registry without a policy';
    END IF;
END $$;
RESET ROLE;

ROLLBACK;
