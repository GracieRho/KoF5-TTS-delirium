-- Fixed synthetic fixture only. This row is routing state, not a conversation
-- log: no transcript, audio, prompt, reply or provider payload is persisted.
-- A patient's refusal belongs to this admission, not to a replaceable iPad
-- Auth UID. There is deliberately no client reset of proactive_paused.
CREATE TABLE kof5.synthetic_conversation_session (
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid),
    encounter_id uuid NOT NULL,
    -- Removing a device Auth user must not erase admission-scoped refusal.
    device_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    session_id uuid NOT NULL DEFAULT gen_random_uuid(),
    version integer NOT NULL CHECK (version > 0),
    state text NOT NULL CHECK (state IN ('IDLE', 'ACTIVE_LISTENING')),
    last_activity timestamptz,
    proactive_paused boolean NOT NULL DEFAULT false,
    -- Combined with session/version CAS, this rejects immediate replay.
    -- It is not an admission-wide idempotency ledger (A/B/A reuse).
    last_client_turn_id uuid NOT NULL,
    PRIMARY KEY (patient_id, encounter_id),
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK ((state = 'ACTIVE_LISTENING') = (last_activity IS NOT NULL)),
    CHECK (NOT proactive_paused OR state = 'IDLE')
);
ALTER TABLE kof5.synthetic_conversation_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_conversation_session FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_conversation_session
    FROM PUBLIC, anon, authenticated, service_role;
-- No direct table policy or Data API view. Only bounded invoker RPC wrappers.

-- This private helper repeats the current admission/assent gate at each RPC.
-- The earlier device_trial_ready helper covers institution approval, three
-- current trial consents and an active test voice profile. Dissent is checked
-- separately so read can show terminal pause while commit always refuses it.
CREATE FUNCTION kof5.synthetic_conversation_device_current(
    p_patient_id uuid, p_encounter_id uuid, p_device_user_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND p_device_user_id = auth.uid()
       AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
       AND kof5.anonymous_auth_user(p_device_user_id)
       AND EXISTS (
           SELECT 1 FROM kof5.patient_device_assignment d
           JOIN kof5.hospital_encounter e
             ON e.encounter_id = d.encounter_id AND e.patient_id = d.patient_id
           JOIN kof5.hospital_patient p ON p.patient_id = d.patient_id
           WHERE d.device_user_id = p_device_user_id
             AND d.patient_id = p_patient_id
             AND d.encounter_id = p_encounter_id
             AND d.status = 'active' AND d.revoked_at IS NULL
             AND d.paired_at <= now() AND d.expires_at > now()
             AND p.active AND e.status = 'in_progress'
             AND e.admitted_at <= now() AND e.discharged_at IS NULL
             AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
       );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_conversation_device_current(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_conversation_device_current(uuid, uuid, uuid)
    TO authenticated;

CREATE FUNCTION kof5.synthetic_conversation_session_read(p_patient_id uuid)
RETURNS TABLE (authorized boolean, encounter_id uuid, session_id uuid,
               version integer, state text, last_activity timestamptz,
               proactive_paused boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_device uuid := auth.uid();
    v_encounter uuid;
    v_existing kof5.synthetic_conversation_session%ROWTYPE;
    v_owner_active boolean;
BEGIN
    SELECT d.encounter_id INTO v_encounter
    FROM kof5.patient_device_assignment d
    WHERE d.device_user_id = v_device AND d.patient_id = p_patient_id
      AND d.status = 'active' AND d.revoked_at IS NULL
      AND d.paired_at <= now() AND d.expires_at > now();
    IF v_encounter IS NULL OR NOT kof5.synthetic_conversation_device_current(
            p_patient_id, v_encounter, v_device) THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::uuid, NULL::integer,
                            NULL::text, NULL::timestamptz, false;
        RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM kof5.safety_audit_event a
        JOIN kof5.hospital_encounter e ON e.encounter_id = v_encounter
        WHERE a.patient_id = p_patient_id AND a.event_type = 'patient_dissent'
          AND a.occurred_at >= e.admitted_at
    ) THEN
        RETURN QUERY SELECT true, v_encounter, NULL::uuid, 0,
                            'IDLE'::text, NULL::timestamptz, true;
        RETURN;
    END IF;
    SELECT s.* INTO v_existing FROM kof5.synthetic_conversation_session s
    WHERE s.patient_id = p_patient_id AND s.encounter_id = v_encounter;
    IF NOT FOUND THEN
        RETURN QUERY SELECT true, v_encounter, NULL::uuid, 0,
                            'IDLE'::text, NULL::timestamptz, false;
        RETURN;
    END IF;
    IF v_existing.device_user_id IS DISTINCT FROM v_device THEN
        SELECT EXISTS (
            SELECT 1 FROM kof5.patient_device_assignment d
            WHERE d.device_user_id = v_existing.device_user_id
              AND d.patient_id = p_patient_id
              AND d.encounter_id = v_encounter
              AND d.status = 'active' AND d.revoked_at IS NULL
              AND d.paired_at <= now() AND d.expires_at > now()
        ) INTO v_owner_active;
        IF v_owner_active THEN
            RETURN QUERY SELECT false, NULL::uuid, NULL::uuid, NULL::integer,
                                NULL::text, NULL::timestamptz, false;
            RETURN;
        END IF;
        -- A new device may take over only after old pairing is terminal. The
        -- pause remains visible and cannot be reset by that takeover.
        RETURN QUERY SELECT true, v_encounter, NULL::uuid, 0,
                            'IDLE'::text, NULL::timestamptz,
                            v_existing.proactive_paused;
        RETURN;
    END IF;
    RETURN QUERY SELECT true, v_encounter, v_existing.session_id,
                        v_existing.version,
                        CASE WHEN v_existing.state = 'ACTIVE_LISTENING'
                                   AND v_existing.last_activity
                                       <= now() - interval '45 seconds'
                             THEN 'IDLE'::text ELSE v_existing.state END,
                        CASE WHEN v_existing.state = 'ACTIVE_LISTENING'
                                   AND v_existing.last_activity
                                       <= now() - interval '45 seconds'
                             THEN NULL::timestamptz
                             ELSE v_existing.last_activity END,
                        v_existing.proactive_paused;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_conversation_session_read(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_conversation_session_read(uuid)
    TO authenticated;
CREATE FUNCTION api.synthetic_conversation_session_read(p_patient_id uuid)
RETURNS TABLE (authorized boolean, encounter_id uuid, session_id uuid,
               version integer, state text, last_activity timestamptz,
               proactive_paused boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_conversation_session_read(p_patient_id);
$$;
REVOKE ALL ON FUNCTION api.synthetic_conversation_session_read(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_conversation_session_read(uuid)
    TO authenticated;

CREATE FUNCTION kof5.synthetic_conversation_session_commit(
    p_patient_id uuid, p_expected_session_id uuid, p_expected_version integer,
    p_new_state text, p_proactive_paused boolean, p_client_turn_id uuid
) RETURNS TABLE (authorized boolean, committed boolean, session_id uuid,
                 version integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_device uuid := auth.uid();
    v_encounter uuid;
    v_existing kof5.synthetic_conversation_session%ROWTYPE;
    v_owner_active boolean;
    v_session_id uuid;
    v_version integer;
BEGIN
    -- Serializes revocation and repeated commits from this device. The
    -- admission-scoped session row below serializes two active iPads.
    SELECT d.encounter_id INTO v_encounter
    FROM kof5.patient_device_assignment d
    WHERE d.device_user_id = v_device AND d.patient_id = p_patient_id
      AND d.status = 'active' AND d.revoked_at IS NULL
      AND d.paired_at <= now() AND d.expires_at > now()
    FOR UPDATE;
    IF v_encounter IS NULL OR NOT kof5.synthetic_conversation_device_current(
            p_patient_id, v_encounter, v_device) THEN
        RETURN QUERY SELECT false, false, NULL::uuid, NULL::integer;
        RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM kof5.safety_audit_event a
        JOIN kof5.hospital_encounter e ON e.encounter_id = v_encounter
        WHERE a.patient_id = p_patient_id AND a.event_type = 'patient_dissent'
          AND a.occurred_at >= e.admitted_at
    ) THEN
        RETURN QUERY SELECT false, false, NULL::uuid, NULL::integer;
        RETURN;
    END IF;
    IF p_expected_version IS NULL OR p_expected_version < 0
       OR p_new_state IS NULL OR p_new_state NOT IN ('IDLE', 'ACTIVE_LISTENING')
       OR p_proactive_paused IS NULL OR p_client_turn_id IS NULL
       OR substring(p_client_turn_id::text, 15, 1) <> '4'
       OR substring(p_client_turn_id::text, 20, 1) NOT IN ('8','9','a','b')
       OR (p_new_state = 'ACTIVE_LISTENING' AND p_proactive_paused) THEN
        RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
        RETURN;
    END IF;
    SELECT s.* INTO v_existing FROM kof5.synthetic_conversation_session s
    WHERE s.patient_id = p_patient_id AND s.encounter_id = v_encounter
    FOR UPDATE;
    IF NOT FOUND THEN
        IF p_expected_session_id IS NOT NULL OR p_expected_version <> 0 THEN
            RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
            RETURN;
        END IF;
        INSERT INTO kof5.synthetic_conversation_session (
            patient_id, encounter_id, device_user_id, version, state,
            last_activity, proactive_paused, last_client_turn_id
        ) VALUES (
            p_patient_id, v_encounter, v_device, 1, p_new_state,
            CASE WHEN p_new_state = 'ACTIVE_LISTENING' THEN now() ELSE NULL END,
            p_proactive_paused, p_client_turn_id
        ) ON CONFLICT (patient_id, encounter_id) DO NOTHING
        RETURNING kof5.synthetic_conversation_session.session_id
        INTO v_session_id;
        IF v_session_id IS NOT NULL AND p_proactive_paused THEN
            INSERT INTO kof5.safety_audit_event (patient_id, event_type)
            VALUES (p_patient_id, 'patient_dissent');
        END IF;
        RETURN QUERY SELECT true, v_session_id IS NOT NULL, v_session_id,
                            CASE WHEN v_session_id IS NOT NULL THEN 1
                                 ELSE NULL::integer END;
        RETURN;
    END IF;
    IF v_existing.proactive_paused AND NOT p_proactive_paused THEN
        RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
        RETURN;
    END IF;
    IF v_existing.last_client_turn_id = p_client_turn_id
       OR (v_existing.device_user_id = v_device
           AND v_existing.version = 2147483647) THEN
        RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
        RETURN;
    END IF;
    IF v_existing.device_user_id IS DISTINCT FROM v_device THEN
        SELECT EXISTS (
            SELECT 1 FROM kof5.patient_device_assignment d
            WHERE d.device_user_id = v_existing.device_user_id
              AND d.patient_id = p_patient_id
              AND d.encounter_id = v_encounter
              AND d.status = 'active' AND d.revoked_at IS NULL
              AND d.paired_at <= now() AND d.expires_at > now()
        ) INTO v_owner_active;
        IF v_owner_active OR v_existing.proactive_paused
           OR p_expected_session_id IS NOT NULL OR p_expected_version <> 0 THEN
            RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
            RETURN;
        END IF;
        UPDATE kof5.synthetic_conversation_session s
        SET device_user_id = v_device, session_id = gen_random_uuid(),
            version = 1, state = p_new_state,
            last_activity = CASE WHEN p_new_state = 'ACTIVE_LISTENING'
                                 THEN now() ELSE NULL END,
            proactive_paused = p_proactive_paused,
            last_client_turn_id = p_client_turn_id
        WHERE s.patient_id = p_patient_id AND s.encounter_id = v_encounter
        RETURNING s.session_id, s.version INTO v_session_id, v_version;
    ELSE
        IF p_expected_session_id IS DISTINCT FROM v_existing.session_id
           OR p_expected_version <> v_existing.version THEN
            RETURN QUERY SELECT true, false, NULL::uuid, NULL::integer;
            RETURN;
        END IF;
        UPDATE kof5.synthetic_conversation_session s
        SET version = s.version + 1, state = p_new_state,
            last_activity = CASE WHEN p_new_state = 'ACTIVE_LISTENING'
                                 THEN now() ELSE NULL END,
            proactive_paused = p_proactive_paused,
            last_client_turn_id = p_client_turn_id
        WHERE s.patient_id = p_patient_id AND s.encounter_id = v_encounter
        RETURNING s.session_id, s.version INTO v_session_id, v_version;
    END IF;
    IF p_proactive_paused AND NOT v_existing.proactive_paused THEN
        INSERT INTO kof5.safety_audit_event (patient_id, event_type)
        VALUES (p_patient_id, 'patient_dissent');
    END IF;
    RETURN QUERY SELECT true, true, v_session_id, v_version;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_conversation_session_commit(
    uuid, uuid, integer, text, boolean, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_conversation_session_commit(
    uuid, uuid, integer, text, boolean, uuid) TO authenticated;
CREATE FUNCTION api.synthetic_conversation_session_commit(
    p_patient_id uuid, p_expected_session_id uuid, p_expected_version integer,
    p_new_state text, p_proactive_paused boolean, p_client_turn_id uuid
) RETURNS TABLE (authorized boolean, committed boolean, session_id uuid,
                 version integer)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_conversation_session_commit(
        p_patient_id, p_expected_session_id, p_expected_version,
        p_new_state, p_proactive_paused, p_client_turn_id);
$$;
REVOKE ALL ON FUNCTION api.synthetic_conversation_session_commit(
    uuid, uuid, integer, text, boolean, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_conversation_session_commit(
    uuid, uuid, integer, text, boolean, uuid) TO authenticated;
