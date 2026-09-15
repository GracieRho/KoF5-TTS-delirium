-- Synthetic patient975 only. This selects an existing guardian clone for a
-- server-held TTS request; it does not authorize clinical use or store audio.
CREATE FUNCTION kof5.synthetic_patient_tts_voice_ready(p_patient_id uuid)
RETURNS TABLE (
    authorized boolean, guardian_user_id uuid, clone_id uuid,
    provider text, voice_id text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    WITH eligible_patient AS (
        SELECT p.patient_id
        FROM kof5.hospital_patient p
        JOIN kof5.hospital_encounter e ON e.patient_id = p.patient_id
        WHERE auth.role() = 'service_role'
          AND p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
          AND p.patient_id = p_patient_id AND p.active
          AND e.status = 'in_progress' AND e.admitted_at <= now()
          AND e.discharged_at IS NULL
          AND kof5.registry_approved(p.hospital_ref)
          AND NOT EXISTS (
              SELECT 1 FROM kof5.safety_audit_event a
              WHERE a.patient_id = p.patient_id
                AND a.event_type = 'patient_dissent'
                AND a.occurred_at >= e.admitted_at
          )
          AND (
              SELECT count(DISTINCT c.scope)
              FROM kof5.consent_record c
              WHERE c.patient_id = p.patient_id
                AND c.scope IN (
                    'patient_participation', 'ambient_processing',
                    'patient_voice_feature'
                )
                AND c.signer_role IN ('patient', 'proxy')
                AND c.status = 'active' AND c.assent_status = 'assented'
                AND c.effective_at <= now() AND c.withdrawn_at IS NULL
                AND (c.expires_at IS NULL OR c.expires_at > now())
          ) = 3
    ), candidates AS (
        SELECT c.guardian_user_id, c.clone_id, c.provider, c.voice_id
        FROM kof5.synthetic_guardian_voice_clone c
        JOIN eligible_patient p ON p.patient_id = c.patient_id
        WHERE c.status = 'created' AND c.voice_id IS NOT NULL
          AND kof5.synthetic_guardian_clone_consent_current(
              c.patient_id, c.guardian_user_id, c.consent_id
          )
    ), single_candidate AS (
        SELECT c.* FROM candidates c
        WHERE (SELECT count(*) FROM candidates) = 1
    )
    SELECT s.clone_id IS NOT NULL, s.guardian_user_id, s.clone_id,
           s.provider, s.voice_id
    FROM (SELECT 1) one_row
    LEFT JOIN single_candidate s ON true;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_patient_tts_voice_ready(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_patient_tts_voice_ready(uuid)
    TO service_role;

CREATE FUNCTION api.synthetic_patient_tts_voice_ready(p_patient_id uuid)
RETURNS TABLE (
    authorized boolean, guardian_user_id uuid, clone_id uuid,
    provider text, voice_id text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_patient_tts_voice_ready(p_patient_id);
$$;
REVOKE ALL ON FUNCTION api.synthetic_patient_tts_voice_ready(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_patient_tts_voice_ready(uuid)
    TO service_role;
