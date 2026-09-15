-- Read-only readiness for a caller's current registrar memberships. The private
-- approval references are never returned through the Data API.
CREATE VIEW api.hospital_registration_ready WITH (security_invoker = true) AS
    SELECT m.hospital_ref, kof5.registry_approved(m.hospital_ref) AS ready
    FROM kof5.hospital_staff_membership m
    WHERE m.auth_user_id = (SELECT auth.uid())
      AND m.product_role = 'registrar' AND m.status = 'verified'
      AND m.effective_at <= now()
      AND (m.expires_at IS NULL OR m.expires_at > now());

REVOKE ALL ON api.hospital_registration_ready FROM PUBLIC, anon, service_role;
GRANT SELECT ON api.hospital_registration_ready TO authenticated;
