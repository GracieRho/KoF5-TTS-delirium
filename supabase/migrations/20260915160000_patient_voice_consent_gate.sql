-- Private synthetic-trial eligibility view. This is not an approved clinical consent flow.
-- Check eligibility again at the moment of use; do not cache an earlier positive result.
CREATE VIEW kof5.usable_patient_voice_profile WITH (security_invoker = true) AS
    SELECT p.profile_id, p.patient_id, p.encounter_id,
           p.embedding_model, p.embedding_version, p.encrypted_embedding_ref
    FROM kof5.patient_voice_profile p
    JOIN kof5.hospital_patient h ON h.patient_id = p.patient_id
    JOIN kof5.hospital_encounter e
      ON e.encounter_id = p.encounter_id AND e.patient_id = p.patient_id
    JOIN kof5.consent_record c
      ON c.consent_id = p.consent_id AND c.patient_id = p.patient_id
    WHERE p.status = 'active' AND p.quality_status = 'accepted'
      AND p.revoked_at IS NULL AND p.deleted_at IS NULL
      AND h.active
      AND e.status = 'in_progress' AND e.admitted_at <= now()
      AND e.discharged_at IS NULL
      AND c.scope = 'patient_voice_feature'
      AND c.signer_role IN ('patient', 'proxy')
      AND c.status = 'active' AND c.assent_status = 'assented'
      AND c.effective_at <= now() AND c.withdrawn_at IS NULL
      AND (c.expires_at IS NULL OR c.expires_at > now());

REVOKE ALL ON kof5.usable_patient_voice_profile
    FROM PUBLIC, anon, authenticated, service_role;
-- No client grant. Institution-approved enrollment, writer and deletion flow are pending.

-- Withdrawal is terminal for this record. A later decision needs a new consent_id,
-- so a stale profile cannot become eligible again by reopening its old consent.
CREATE FUNCTION kof5.prevent_withdrawn_consent_reactivation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF OLD.status = 'withdrawn' AND NEW.status <> 'withdrawn' THEN
        RAISE EXCEPTION 'withdrawn consent requires a new record' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION kof5.prevent_withdrawn_consent_reactivation()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER withdrawn_consent_is_terminal
    BEFORE UPDATE ON kof5.consent_record
    FOR EACH ROW EXECUTE FUNCTION kof5.prevent_withdrawn_consent_reactivation();
