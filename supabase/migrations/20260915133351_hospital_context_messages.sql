-- Hospital-approved facts and verbatim messages for current encounters.
-- Creation/approval/delivery remain a privileged institution workflow; clients read only.

CREATE TABLE kof5.hospital_context_fact (
    fact_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES kof5.hospital_patient (patient_id),
    encounter_id uuid,
    category text NOT NULL CHECK (length(trim(category)) > 0),
    content text NOT NULL CHECK (length(trim(content)) > 0),
    source_staff_ref text NOT NULL CHECK (length(trim(source_staff_ref)) > 0),
    approved_by_staff_ref text,
    verified_at timestamptz,
    valid_until timestamptz,
    status text NOT NULL CHECK (status IN ('draft', 'approved', 'revoked')),
    revoked_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK (encounter_id IS NOT NULL OR category = 'hospital'),
    CHECK (status <> 'approved' OR (
        approved_by_staff_ref IS NOT NULL AND length(trim(approved_by_staff_ref)) > 0
        AND verified_at IS NOT NULL
    )),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL),
    CHECK (valid_until IS NULL OR (verified_at IS NOT NULL AND valid_until > verified_at))
);

CREATE INDEX hospital_context_fact_patient_idx
    ON kof5.hospital_context_fact (patient_id, status, valid_until);

CREATE TABLE kof5.hospital_message (
    message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL,
    encounter_id uuid NOT NULL,
    approved_text text NOT NULL CHECK (length(trim(approved_text)) > 0),
    approved_by_staff_ref text NOT NULL CHECK (length(trim(approved_by_staff_ref)) > 0),
    approved_at timestamptz NOT NULL,
    due_at timestamptz NOT NULL,
    delivery_status text NOT NULL DEFAULT 'pending'
        CHECK (delivery_status IN ('pending', 'delivered', 'cancelled')),
    delivered_at timestamptz,
    cancelled_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK ((delivery_status = 'delivered') = (delivered_at IS NOT NULL)),
    CHECK ((delivery_status = 'cancelled') = (cancelled_at IS NOT NULL)),
    CHECK (delivered_at IS NULL OR delivered_at >= approved_at)
);

CREATE INDEX hospital_message_due_idx
    ON kof5.hospital_message (patient_id, delivery_status, due_at);

CREATE FUNCTION kof5.keep_approved_hospital_message() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF NEW.approved_text IS DISTINCT FROM OLD.approved_text
       OR NEW.approved_by_staff_ref IS DISTINCT FROM OLD.approved_by_staff_ref
       OR NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
        RAISE EXCEPTION 'approved hospital message text and attribution are immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER hospital_message_approval_immutable
    BEFORE UPDATE OF approved_text, approved_by_staff_ref, approved_at
    ON kof5.hospital_message
    FOR EACH ROW EXECUTE FUNCTION kof5.keep_approved_hospital_message();

ALTER TABLE kof5.hospital_context_fact ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_context_fact FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_message ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_message FORCE ROW LEVEL SECURITY;

CREATE POLICY hospital_context_verified_staff_read ON kof5.hospital_context_fact
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM kof5.hospital_patient p
        WHERE p.patient_id = hospital_context_fact.patient_id
    ));

CREATE POLICY hospital_message_verified_staff_read ON kof5.hospital_message
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM kof5.hospital_patient p
        WHERE p.patient_id = hospital_message.patient_id
    ));

REVOKE ALL ON kof5.hospital_context_fact, kof5.hospital_message
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON kof5.hospital_context_fact, kof5.hospital_message TO authenticated;

CREATE VIEW api.hospital_context_current WITH (security_invoker = true) AS
    SELECT f.fact_id, f.patient_id, f.encounter_id, f.category, f.content,
           f.verified_at, f.valid_until
    FROM kof5.hospital_context_fact f
    JOIN kof5.hospital_patient p ON p.patient_id = f.patient_id
    JOIN kof5.hospital_encounter e
      ON e.patient_id = p.patient_id AND e.status = 'in_progress'
    WHERE p.active AND f.status = 'approved' AND f.verified_at <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND (f.encounter_id = e.encounter_id
           OR (f.encounter_id IS NULL AND f.category = 'hospital'));

CREATE VIEW api.hospital_message_list WITH (security_invoker = true) AS
    SELECT m.message_id, m.patient_id, m.encounter_id, m.approved_text,
           m.approved_by_staff_ref, m.approved_at, m.due_at,
           m.delivery_status, m.delivered_at, m.cancelled_at
    FROM kof5.hospital_message m
    JOIN kof5.hospital_patient p ON p.patient_id = m.patient_id
    JOIN kof5.hospital_encounter e ON e.encounter_id = m.encounter_id
    WHERE p.active AND e.status = 'in_progress';

REVOKE ALL ON api.hospital_context_current, api.hospital_message_list
    FROM PUBLIC, anon, service_role;
GRANT SELECT ON api.hospital_context_current, api.hospital_message_list
    TO authenticated;
