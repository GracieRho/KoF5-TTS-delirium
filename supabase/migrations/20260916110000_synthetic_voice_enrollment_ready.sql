-- Synthetic fixture 975 only. This read-only gate does not enroll a voice,
-- grant patient use or approve identity/ambient audio/clinical escalation.
-- A profile is intentionally not required: this reports prerequisites for
-- the first staff-led enrollment, before a profile exists.
CREATE FUNCTION kof5.synthetic_voice_enrollment_ready()
RETURNS TABLE (ready boolean, patient_id uuid, voice_profile_state text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_patient constant uuid := '00000000-0000-4000-8000-000000000975'::uuid;
    v_encounter uuid;
    v_admitted_at timestamptz;
    v_profile_state text;
    v_ready boolean;
BEGIN
    IF NOT kof5.synthetic_assigned_care_staff(v_patient) THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;

    SELECT e.encounter_id, e.admitted_at INTO v_encounter, v_admitted_at
    FROM kof5.hospital_patient p
    JOIN kof5.hospital_encounter e ON e.patient_id = p.patient_id
    WHERE p.patient_id = v_patient AND p.active
      AND e.status = 'in_progress' AND e.admitted_at <= now()
      AND e.discharged_at IS NULL;
    IF v_encounter IS NULL THEN
        RETURN QUERY SELECT false, v_patient, 'none'::text;
        RETURN;
    END IF;

    SELECT p.status INTO v_profile_state
    FROM kof5.patient_voice_profile p
    WHERE p.patient_id = v_patient AND p.encounter_id = v_encounter
    ORDER BY CASE p.status WHEN 'active' THEN 0 WHEN 'pending' THEN 1
                           WHEN 'revoked' THEN 2 ELSE 3 END,
             p.enrolled_at DESC NULLS LAST, p.profile_id
    LIMIT 1;

    SELECT kof5.registry_approved(p.hospital_ref)
       AND NOT EXISTS (
           SELECT 1 FROM kof5.safety_audit_event a
           WHERE a.patient_id = v_patient AND a.event_type = 'patient_dissent'
             AND a.occurred_at >= v_admitted_at
       )
       AND EXISTS (
           SELECT 1 FROM kof5.consent_record c
           WHERE c.patient_id = v_patient AND c.scope = 'patient_participation'
             AND c.signer_role IN ('patient', 'proxy')
             AND c.status = 'active' AND c.assent_status = 'assented'
             AND c.effective_at <= now() AND c.withdrawn_at IS NULL
             AND (c.expires_at IS NULL OR c.expires_at > now())
       )
       AND EXISTS (
           SELECT 1 FROM kof5.consent_record c
           WHERE c.patient_id = v_patient AND c.scope = 'patient_voice_feature'
             AND c.signer_role IN ('patient', 'proxy')
             AND c.status = 'active' AND c.assent_status = 'assented'
             AND c.effective_at <= now() AND c.withdrawn_at IS NULL
             AND (c.expires_at IS NULL OR c.expires_at > now())
       ) INTO v_ready
    FROM kof5.hospital_patient p WHERE p.patient_id = v_patient;
    RETURN QUERY SELECT COALESCE(v_ready, false), v_patient,
                        COALESCE(v_profile_state, 'none');
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_voice_enrollment_ready()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_voice_enrollment_ready()
    TO authenticated;

CREATE FUNCTION api.synthetic_voice_enrollment_ready()
RETURNS TABLE (ready boolean, patient_id uuid, voice_profile_state text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_voice_enrollment_ready();
$$;
REVOKE ALL ON FUNCTION api.synthetic_voice_enrollment_ready()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_voice_enrollment_ready()
    TO authenticated;
