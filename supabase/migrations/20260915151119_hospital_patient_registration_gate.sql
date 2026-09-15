-- Hospital patient registration stays default-deny until a trusted server records
-- institution and clinical-safety approval for this hospital. Never seed this
-- gate on a real project with synthetic TEST approvals.

CREATE TABLE kof5.hospital_registry_activation (
    hospital_ref text PRIMARY KEY,
    status text NOT NULL CHECK (status IN ('approved', 'revoked')),
    institution_approval_ref text NOT NULL CHECK (length(trim(institution_approval_ref)) > 0),
    clinical_safety_approval_ref text NOT NULL CHECK (length(trim(clinical_safety_approval_ref)) > 0),
    approved_at timestamptz NOT NULL,
    expires_at timestamptz,
    revoked_at timestamptz,
    CHECK (length(trim(hospital_ref)) > 0),
    CHECK (expires_at IS NULL OR expires_at > approved_at),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL)
);
ALTER TABLE kof5.hospital_registry_activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.hospital_registry_activation FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.hospital_registry_activation FROM PUBLIC, anon, authenticated, service_role;

-- Private helper reads the server-only activation table. It is not in the exposed
-- api schema and takes no client-supplied approval claims.
CREATE FUNCTION kof5.registry_approved(_hospital_ref text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM kof5.hospital_registry_activation g
        WHERE g.hospital_ref = _hospital_ref
          AND g.status = 'approved' AND g.approved_at <= now()
          AND (g.expires_at IS NULL OR g.expires_at > now())
    );
$$;
REVOKE ALL ON FUNCTION kof5.registry_approved(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION kof5.registry_approved(text) TO authenticated;

-- The Data API view omits the registrar identity field. Its base-table default
-- records the signed-in Auth user, and the INSERT policy verifies it again.
ALTER TABLE kof5.hospital_patient
    ALTER COLUMN registered_by_staff_ref SET DEFAULT (auth.uid())::text;
CREATE POLICY hospital_patient_approved_registrar_insert ON kof5.hospital_patient
    FOR INSERT TO authenticated
    WITH CHECK (
        registered_by_staff_ref = (SELECT auth.uid())::text
        AND kof5.registry_approved(hospital_ref)
        AND EXISTS (
            SELECT 1 FROM kof5.hospital_staff_membership m
            WHERE m.auth_user_id = (SELECT auth.uid())
              AND m.hospital_ref = hospital_patient.hospital_ref
              AND m.product_role = 'registrar' AND m.status = 'verified'
              AND m.effective_at <= now()
              AND (m.expires_at IS NULL OR m.expires_at > now())
        )
    );
GRANT INSERT (hospital_ref, ehr_patient_ref, staff_display_name,
    birth_date, administrative_gender, preferred_language)
    ON kof5.hospital_patient TO authenticated;

CREATE VIEW api.hospital_patient_registration WITH (security_invoker = true) AS
    SELECT hospital_ref, ehr_patient_ref, staff_display_name,
           birth_date, administrative_gender, preferred_language
    FROM kof5.hospital_patient;
REVOKE ALL ON api.hospital_patient_registration FROM PUBLIC, anon, service_role;
GRANT INSERT ON api.hospital_patient_registration TO authenticated;
-- No UPDATE/DELETE or direct Data API access to the private registry is granted.
