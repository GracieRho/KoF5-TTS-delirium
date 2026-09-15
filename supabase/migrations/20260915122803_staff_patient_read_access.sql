-- Read-only, verified hospital access for Supabase Auth users.
-- Memberships/assignments are written only by an institution-verified server workflow.
-- The private registry stays outside the Data API; the invoker view is the only exposed read surface.

ALTER TABLE kof5.hospital_patient
    ADD CONSTRAINT hospital_patient_id_hospital_unique UNIQUE (patient_id, hospital_ref);

CREATE TABLE kof5.hospital_staff_membership (
    membership_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
    hospital_ref text NOT NULL,
    product_role text NOT NULL CHECK (product_role IN ('registrar', 'care_staff')),
    status text NOT NULL CHECK (status IN ('pending', 'verified', 'revoked')),
    effective_at timestamptz,
    expires_at timestamptz,
    verified_by_staff_ref text,
    verified_at timestamptz,
    revoked_at timestamptz,
    UNIQUE (membership_id, hospital_ref),
    CHECK (length(trim(hospital_ref)) > 0),
    CHECK (status <> 'verified' OR (
        effective_at IS NOT NULL AND verified_at IS NOT NULL
        AND verified_by_staff_ref IS NOT NULL AND length(trim(verified_by_staff_ref)) > 0
    )),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL),
    CHECK (expires_at IS NULL OR (effective_at IS NOT NULL AND expires_at > effective_at))
);

CREATE UNIQUE INDEX one_verified_staff_membership_per_hospital
    ON kof5.hospital_staff_membership (auth_user_id, hospital_ref)
    WHERE status = 'verified';
CREATE INDEX hospital_staff_membership_auth_idx
    ON kof5.hospital_staff_membership (auth_user_id, hospital_ref);

CREATE TABLE kof5.hospital_staff_assignment (
    assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id uuid NOT NULL,
    hospital_ref text NOT NULL,
    patient_id uuid NOT NULL,
    status text NOT NULL CHECK (status IN ('pending', 'verified', 'revoked')),
    effective_at timestamptz,
    expires_at timestamptz,
    verified_by_staff_ref text,
    verified_at timestamptz,
    revoked_at timestamptz,
    FOREIGN KEY (membership_id, hospital_ref)
        REFERENCES kof5.hospital_staff_membership (membership_id, hospital_ref),
    FOREIGN KEY (patient_id, hospital_ref)
        REFERENCES kof5.hospital_patient (patient_id, hospital_ref),
    CHECK (status <> 'verified' OR (
        effective_at IS NOT NULL AND verified_at IS NOT NULL
        AND verified_by_staff_ref IS NOT NULL AND length(trim(verified_by_staff_ref)) > 0
    )),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL),
    CHECK (expires_at IS NULL OR (effective_at IS NOT NULL AND expires_at > effective_at))
);

CREATE UNIQUE INDEX one_verified_staff_assignment_per_patient
    ON kof5.hospital_staff_assignment (membership_id, patient_id)
    WHERE status = 'verified';
CREATE INDEX hospital_staff_assignment_patient_idx
    ON kof5.hospital_staff_assignment (patient_id, membership_id);

ALTER TABLE kof5.hospital_staff_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_staff_membership FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_staff_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_staff_assignment FORCE ROW LEVEL SECURITY;

CREATE POLICY staff_membership_self_read ON kof5.hospital_staff_membership
    FOR SELECT TO authenticated
    USING (auth_user_id = (SELECT auth.uid()));

CREATE POLICY staff_assignment_self_read ON kof5.hospital_staff_assignment
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM kof5.hospital_staff_membership m
        WHERE m.membership_id = hospital_staff_assignment.membership_id
          AND m.auth_user_id = (SELECT auth.uid())
    ));

CREATE POLICY hospital_patient_verified_staff_read ON kof5.hospital_patient
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM kof5.hospital_staff_membership m
            WHERE m.auth_user_id = (SELECT auth.uid())
              AND m.hospital_ref = hospital_patient.hospital_ref
              AND m.product_role = 'registrar' AND m.status = 'verified'
              AND m.effective_at <= now()
              AND (m.expires_at IS NULL OR m.expires_at > now())
        ) OR EXISTS (
            SELECT 1 FROM kof5.hospital_staff_assignment a
            JOIN kof5.hospital_staff_membership m ON m.membership_id = a.membership_id
            WHERE a.patient_id = hospital_patient.patient_id
              AND a.hospital_ref = hospital_patient.hospital_ref
              AND a.status = 'verified' AND a.effective_at <= now()
              AND (a.expires_at IS NULL OR a.expires_at > now())
              AND m.auth_user_id = (SELECT auth.uid())
              AND m.product_role = 'care_staff' AND m.status = 'verified'
              AND m.effective_at <= now()
              AND (m.expires_at IS NULL OR m.expires_at > now())
        )
    );

CREATE POLICY hospital_encounter_verified_staff_read ON kof5.hospital_encounter
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM kof5.hospital_patient p
        WHERE p.patient_id = hospital_encounter.patient_id
    ));

REVOKE ALL ON SCHEMA kof5 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON kof5.hospital_patient, kof5.hospital_encounter,
    kof5.consent_record, kof5.patient_voice_profile, kof5.patient_voice_sample,
    kof5.hospital_staff_membership, kof5.hospital_staff_assignment
    FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA kof5 TO authenticated;
GRANT SELECT ON kof5.hospital_staff_membership TO authenticated;
GRANT SELECT ON kof5.hospital_staff_assignment TO authenticated;
GRANT SELECT ON kof5.hospital_patient TO authenticated;
GRANT SELECT ON kof5.hospital_encounter TO authenticated;
-- No authenticated grants are added to consent, voice profile or voice sample tables.

CREATE SCHEMA api;
CREATE VIEW api.hospital_patient_list WITH (security_invoker = true) AS
    SELECT p.patient_id, p.hospital_ref, p.ehr_patient_ref, p.staff_display_name,
           p.birth_date, p.preferred_language,
           e.encounter_id, e.status AS encounter_status,
           e.ward_ref, e.room_ref, e.bed_ref
    FROM kof5.hospital_patient p
    LEFT JOIN kof5.hospital_encounter e
      ON e.patient_id = p.patient_id AND e.status = 'in_progress'
    WHERE p.active;

REVOKE ALL ON SCHEMA api FROM PUBLIC, anon, service_role;
GRANT USAGE ON SCHEMA api TO authenticated;
REVOKE ALL ON api.hospital_patient_list FROM PUBLIC, anon, service_role;
GRANT SELECT ON api.hospital_patient_list TO authenticated;
