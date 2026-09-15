-- A guardian may read/write family memories only after institution-verified patient linkage.
-- Verification is a privileged hospital workflow, not a client self-service action.
-- Patient identifiers, encounters, consent and voice tables remain inaccessible to guardians.

CREATE TABLE kof5.patient_guardian_link (
    link_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL REFERENCES kof5.hospital_patient (patient_id),
    guardian_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
    relationship text NOT NULL CHECK (length(trim(relationship)) > 0),
    is_primary boolean NOT NULL DEFAULT false,
    access_status text NOT NULL CHECK (access_status IN ('pending', 'verified', 'revoked')),
    effective_at timestamptz,
    expires_at timestamptz,
    verified_by_staff_ref text,
    verified_at timestamptz,
    revoked_at timestamptz,
    UNIQUE (patient_id, guardian_user_id),
    CHECK (access_status <> 'verified' OR (
        effective_at IS NOT NULL AND verified_at IS NOT NULL
        AND verified_by_staff_ref IS NOT NULL AND length(trim(verified_by_staff_ref)) > 0
    )),
    CHECK (access_status <> 'revoked' OR revoked_at IS NOT NULL),
    CHECK (expires_at IS NULL OR (effective_at IS NOT NULL AND expires_at > effective_at))
);

CREATE INDEX patient_guardian_link_user_idx
    ON kof5.patient_guardian_link (guardian_user_id, patient_id);

CREATE TABLE kof5.family_fact (
    fact_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL,
    author_guardian_user_id uuid NOT NULL,
    category text NOT NULL CHECK (length(trim(category)) > 0),
    content text NOT NULL CHECK (length(trim(content)) > 0),
    sensitivity text NOT NULL DEFAULT 'ordinary'
        CHECK (sensitivity IN ('ordinary', 'sensitive')),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (patient_id, author_guardian_user_id)
        REFERENCES kof5.patient_guardian_link (patient_id, guardian_user_id),
    CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE INDEX family_fact_author_idx
    ON kof5.family_fact (author_guardian_user_id, patient_id);

ALTER TABLE kof5.patient_guardian_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_guardian_link FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_fact ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_fact FORCE ROW LEVEL SECURITY;

CREATE POLICY guardian_own_link_read ON kof5.patient_guardian_link
    FOR SELECT TO authenticated
    USING (guardian_user_id = (SELECT auth.uid()));

CREATE POLICY guardian_current_family_fact_read ON kof5.family_fact
    FOR SELECT TO authenticated
    USING (author_guardian_user_id = (SELECT auth.uid()) AND EXISTS (
        SELECT 1 FROM kof5.patient_guardian_link l
        WHERE l.patient_id = family_fact.patient_id
          AND l.guardian_user_id = (SELECT auth.uid())
          AND l.access_status = 'verified' AND l.effective_at <= now()
          AND (l.expires_at IS NULL OR l.expires_at > now())
    ));

CREATE POLICY guardian_current_family_fact_insert ON kof5.family_fact
    FOR INSERT TO authenticated
    WITH CHECK (author_guardian_user_id = (SELECT auth.uid()) AND EXISTS (
        SELECT 1 FROM kof5.patient_guardian_link l
        WHERE l.patient_id = family_fact.patient_id
          AND l.guardian_user_id = (SELECT auth.uid())
          AND l.access_status = 'verified' AND l.effective_at <= now()
          AND (l.expires_at IS NULL OR l.expires_at > now())
    ));

CREATE POLICY guardian_current_family_fact_update ON kof5.family_fact
    FOR UPDATE TO authenticated
    USING (author_guardian_user_id = (SELECT auth.uid()) AND EXISTS (
        SELECT 1 FROM kof5.patient_guardian_link l
        WHERE l.patient_id = family_fact.patient_id
          AND l.guardian_user_id = (SELECT auth.uid())
          AND l.access_status = 'verified' AND l.effective_at <= now()
          AND (l.expires_at IS NULL OR l.expires_at > now())
    ))
    WITH CHECK (author_guardian_user_id = (SELECT auth.uid()) AND EXISTS (
        SELECT 1 FROM kof5.patient_guardian_link l
        WHERE l.patient_id = family_fact.patient_id
          AND l.guardian_user_id = (SELECT auth.uid())
          AND l.access_status = 'verified' AND l.effective_at <= now()
          AND (l.expires_at IS NULL OR l.expires_at > now())
    ));

REVOKE ALL ON kof5.patient_guardian_link, kof5.family_fact
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON kof5.patient_guardian_link TO authenticated;
GRANT SELECT, INSERT, UPDATE ON kof5.family_fact TO authenticated;

CREATE VIEW api.guardian_links WITH (security_invoker = true) AS
    SELECT link_id, patient_id, relationship, is_primary, access_status,
           effective_at, expires_at, verified_at
    FROM kof5.patient_guardian_link;

CREATE VIEW api.family_context WITH (security_invoker = true) AS
    SELECT fact_id, patient_id, author_guardian_user_id, category, content,
           sensitivity, valid_from, valid_until, active, created_at
    FROM kof5.family_fact;

REVOKE ALL ON api.guardian_links, api.family_context
    FROM PUBLIC, anon, service_role;
GRANT SELECT ON api.guardian_links TO authenticated;
GRANT SELECT, INSERT, UPDATE ON api.family_context TO authenticated;
