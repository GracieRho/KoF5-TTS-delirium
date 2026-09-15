-- PostgreSQL-only draft of PRD hospital registry/voice tables.
-- No application role/policy is installed: every table is FORCE RLS, default-deny.
-- Do not deploy with patient data until institution-approved auth, consent and deletion flows exist.

CREATE SCHEMA kof5;

CREATE TABLE kof5.hospital_patient (
    patient_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_ref text NOT NULL,
    ehr_patient_ref text NOT NULL,
    staff_display_name text NOT NULL,
    birth_date date,
    administrative_gender text,
    preferred_language text NOT NULL DEFAULT 'ko',
    active boolean NOT NULL DEFAULT true,
    registered_by_staff_ref text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (hospital_ref, ehr_patient_ref),
    CHECK (length(trim(hospital_ref)) > 0),
    CHECK (length(trim(ehr_patient_ref)) > 0),
    CHECK (length(trim(staff_display_name)) > 0),
    CHECK (length(trim(registered_by_staff_ref)) > 0),
    CHECK (administrative_gender IS NULL OR administrative_gender IN ('female', 'male', 'other', 'unknown'))
);

CREATE TABLE kof5.hospital_encounter (
    encounter_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES kof5.hospital_patient (patient_id),
    ehr_encounter_ref text NOT NULL,
    status text NOT NULL CHECK (status IN ('planned', 'in_progress', 'finished', 'cancelled')),
    admitted_at timestamptz,
    discharged_at timestamptz,
    ward_ref text,
    room_ref text,
    bed_ref text,
    care_team_ref text,
    location_verified_at timestamptz,
    UNIQUE (patient_id, ehr_encounter_ref),
    UNIQUE (encounter_id, patient_id),
    CHECK (length(trim(ehr_encounter_ref)) > 0),
    CHECK (status <> 'in_progress' OR admitted_at IS NOT NULL),
    CHECK (status <> 'in_progress' OR discharged_at IS NULL),
    CHECK (status <> 'finished' OR discharged_at IS NOT NULL),
    CHECK (discharged_at IS NULL OR (admitted_at IS NOT NULL AND discharged_at >= admitted_at))
);

CREATE UNIQUE INDEX one_current_encounter_per_patient
    ON kof5.hospital_encounter (patient_id) WHERE status = 'in_progress';

CREATE TABLE kof5.consent_record (
    consent_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES kof5.hospital_patient (patient_id),
    guardian_ref text,
    scope text NOT NULL CHECK (scope IN (
        'patient_participation', 'patient_voice_feature', 'guardian_voice_clone', 'ambient_processing'
    )),
    signer_role text NOT NULL CHECK (signer_role IN ('patient', 'proxy', 'guardian')),
    signer_ref text NOT NULL,
    assent_status text NOT NULL CHECK (assent_status IN (
        'assented', 'declined', 'not_attempted', 'not_required'
    )),
    status text NOT NULL CHECK (status IN ('draft', 'active', 'expired', 'withdrawn')),
    effective_at timestamptz,
    expires_at timestamptz,
    withdrawn_at timestamptz,
    recorded_by_staff_ref text NOT NULL,
    UNIQUE (consent_id, patient_id, scope),
    CHECK (length(trim(signer_ref)) > 0),
    CHECK (length(trim(recorded_by_staff_ref)) > 0),
    CHECK (guardian_ref IS NULL OR length(trim(guardian_ref)) > 0),
    CHECK (scope <> 'guardian_voice_clone' OR guardian_ref IS NOT NULL),
    CHECK (scope <> 'guardian_voice_clone' OR signer_role = 'guardian'),
    CHECK (status <> 'active' OR effective_at IS NOT NULL),
    CHECK (status <> 'active' OR assent_status <> 'declined'),
    CHECK (status <> 'withdrawn' OR withdrawn_at IS NOT NULL),
    CHECK (expires_at IS NULL OR (effective_at IS NOT NULL AND expires_at > effective_at)),
    CHECK (withdrawn_at IS NULL OR (effective_at IS NOT NULL AND withdrawn_at >= effective_at))
);

CREATE UNIQUE INDEX one_active_patient_consent_per_scope
    ON kof5.consent_record (patient_id, scope)
    WHERE status = 'active' AND scope <> 'guardian_voice_clone';
CREATE UNIQUE INDEX one_active_guardian_clone_consent
    ON kof5.consent_record (patient_id, guardian_ref)
    WHERE status = 'active' AND scope = 'guardian_voice_clone';

CREATE TABLE kof5.patient_voice_profile (
    profile_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES kof5.hospital_patient (patient_id),
    encounter_id uuid NOT NULL,
    consent_id uuid NOT NULL,
    consent_scope text NOT NULL DEFAULT 'patient_voice_feature'
        CHECK (consent_scope = 'patient_voice_feature'),
    status text NOT NULL CHECK (status IN ('pending', 'active', 'revoked', 'deleted')),
    enrollment_duration_ms integer,
    embedding_model text,
    embedding_version text,
    encrypted_embedding_ref text,
    quality_status text NOT NULL CHECK (quality_status IN ('pending', 'accepted', 'rejected')),
    enrolled_by_staff_ref text NOT NULL,
    enrolled_at timestamptz,
    revoked_at timestamptz,
    deleted_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    FOREIGN KEY (consent_id, patient_id, consent_scope)
        REFERENCES kof5.consent_record (consent_id, patient_id, scope),
    CHECK (enrollment_duration_ms IS NULL OR enrollment_duration_ms > 0),
    CHECK (length(trim(enrolled_by_staff_ref)) > 0),
    CHECK (status <> 'active' OR (
        quality_status = 'accepted' AND enrollment_duration_ms IS NOT NULL
        AND embedding_model IS NOT NULL AND length(trim(embedding_model)) > 0
        AND embedding_version IS NOT NULL AND length(trim(embedding_version)) > 0
        AND encrypted_embedding_ref IS NOT NULL AND length(trim(encrypted_embedding_ref)) > 0
        AND enrolled_at IS NOT NULL
    )),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL),
    CHECK (status <> 'deleted' OR deleted_at IS NOT NULL)
);

CREATE UNIQUE INDEX one_active_voice_profile_per_encounter
    ON kof5.patient_voice_profile (patient_id, encounter_id) WHERE status = 'active';

CREATE TABLE kof5.patient_voice_sample (
    sample_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id uuid NOT NULL REFERENCES kof5.patient_voice_profile (profile_id),
    temporary_encrypted_object_ref text,
    codec text NOT NULL CHECK (codec IN ('pcm16_wav', 'flac')),
    duration_ms integer NOT NULL CHECK (duration_ms > 0 AND duration_ms <= 30000),
    captured_at timestamptz NOT NULL,
    purge_due_at timestamptz NOT NULL,
    purged_at timestamptz,
    CHECK (purge_due_at > captured_at),
    CHECK (purged_at IS NULL OR (purged_at >= captured_at AND temporary_encrypted_object_ref IS NULL))
);

CREATE INDEX hospital_encounter_patient_idx ON kof5.hospital_encounter (patient_id);
CREATE INDEX consent_record_patient_idx ON kof5.consent_record (patient_id);
CREATE INDEX voice_profile_patient_idx ON kof5.patient_voice_profile (patient_id);
CREATE INDEX voice_sample_profile_idx ON kof5.patient_voice_sample (profile_id);

ALTER TABLE kof5.hospital_patient ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_patient FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_encounter ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_encounter FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.consent_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.consent_record FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_voice_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_voice_profile FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_voice_sample ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_voice_sample FORCE ROW LEVEL SECURITY;
