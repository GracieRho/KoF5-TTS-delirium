-- Current DB prerequisites for a patient voice feature trial. This is not
-- clinical trial readiness: identity disclosure and alert delivery still need
-- institution-approved workflows before any patient use.
CREATE VIEW kof5.voice_profile_with_trial_consents WITH (security_invoker = true) AS
    SELECT v.profile_id, v.patient_id, v.encounter_id,
           v.embedding_model, v.embedding_version, v.encrypted_embedding_ref
    FROM kof5.usable_patient_voice_profile v
    JOIN kof5.hospital_patient h ON h.patient_id = v.patient_id
    WHERE kof5.registry_approved(h.hospital_ref)
      AND EXISTS (
          SELECT 1 FROM kof5.consent_record c
          WHERE c.patient_id = v.patient_id
            AND c.scope = 'patient_participation'
            AND c.signer_role IN ('patient', 'proxy')
            AND c.status = 'active' AND c.assent_status = 'assented'
            AND c.effective_at <= now() AND c.withdrawn_at IS NULL
            AND (c.expires_at IS NULL OR c.expires_at > now())
      )
      AND EXISTS (
          SELECT 1 FROM kof5.consent_record c
          WHERE c.patient_id = v.patient_id
            AND c.scope = 'ambient_processing'
            AND c.signer_role IN ('patient', 'proxy')
            AND c.status = 'active' AND c.assent_status = 'assented'
            AND c.effective_at <= now() AND c.withdrawn_at IS NULL
            AND (c.expires_at IS NULL OR c.expires_at > now())
      );

REVOKE ALL ON kof5.voice_profile_with_trial_consents
    FROM PUBLIC, anon, authenticated, service_role;
-- No patient app or Data API grant; identity and clinical alert gates remain closed.
