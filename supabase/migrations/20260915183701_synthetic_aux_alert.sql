-- Internal synthetic auxiliary alert only. No patient speech, audio or clinical dispatch.
-- ALERT_CREATED means a DB row, DELIVERED means a staff portal render receipt,
-- and ACKNOWLEDGED requires an assigned care_staff click; none replaces nurse-call.
CREATE TABLE kof5.synthetic_aux_alert (
    alert_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ),
    encounter_id uuid NOT NULL,
    device_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
    idempotency_key uuid NOT NULL,
    risk_category text NOT NULL CHECK (risk_category IN (
        'breathing', 'chest_pain', 'fall', 'pain', 'dizziness', 'distress'
    )),
    state text NOT NULL DEFAULT 'created' CHECK (state IN (
        'created', 'delivered', 'acknowledged', 'resolved', 'failed'
    )),
    created_at timestamptz NOT NULL DEFAULT now(),
    delivered_at timestamptz,
    delivered_by_auth_user_id uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
    acknowledged_at timestamptz,
    acknowledged_by_auth_user_id uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
    resolved_at timestamptz,
    resolved_by_auth_user_id uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
    failed_at timestamptz,
    failure_reason text CHECK (failure_reason IN ('delivery_timeout', 'ack_timeout')),
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    UNIQUE (device_user_id, idempotency_key),
    CHECK (state NOT IN ('delivered', 'acknowledged', 'resolved')
        OR (delivered_at IS NOT NULL AND delivered_by_auth_user_id IS NOT NULL)),
    CHECK (state NOT IN ('acknowledged', 'resolved')
        OR (acknowledged_at IS NOT NULL AND acknowledged_by_auth_user_id IS NOT NULL)),
    CHECK ((state = 'resolved') = (resolved_at IS NOT NULL)),
    CHECK ((state = 'failed') = (failed_at IS NOT NULL)),
    CHECK ((state = 'failed') = (failure_reason IS NOT NULL))
);
CREATE INDEX synthetic_aux_alert_patient_time_idx
    ON kof5.synthetic_aux_alert (patient_id, created_at DESC, alert_id);
CREATE INDEX synthetic_aux_alert_timeout_idx
    ON kof5.synthetic_aux_alert (state, created_at, delivered_at)
    WHERE state IN ('created', 'delivered');
ALTER TABLE kof5.synthetic_aux_alert ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_aux_alert FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_aux_alert FROM PUBLIC, anon, authenticated, service_role;

-- Resolution has no payload; extend the bounded audit event vocabulary.
ALTER TABLE kof5.safety_audit_event
    DROP CONSTRAINT safety_audit_event_event_type_check;
ALTER TABLE kof5.safety_audit_event
    ADD CONSTRAINT safety_audit_event_event_type_check CHECK (event_type IN (
        'patient_dissent', 'identity_question', 'ambient_audio_discarded',
        'high_risk_utterance_detected', 'alert_created', 'alert_delivered',
        'alert_acknowledged', 'alert_failed', 'alert_resolved',
        'conversation_force_stopped'
    ));

CREATE FUNCTION kof5.synthetic_assigned_care_staff(p_patient_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND auth.uid() IS NOT NULL
       AND NOT COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, true)
       AND NOT kof5.anonymous_auth_user(auth.uid())
       AND EXISTS (
           SELECT 1 FROM kof5.hospital_staff_assignment a
           JOIN kof5.hospital_staff_membership m
             ON m.membership_id = a.membership_id
           WHERE a.patient_id = p_patient_id
             AND a.hospital_ref = m.hospital_ref
             AND a.status = 'verified' AND a.effective_at <= now()
             AND (a.expires_at IS NULL OR a.expires_at > now())
             AND m.auth_user_id = auth.uid()
             AND m.product_role = 'care_staff' AND m.status = 'verified'
             AND m.effective_at <= now()
             AND (m.expires_at IS NULL OR m.expires_at > now())
       );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_assigned_care_staff(uuid)
    FROM PUBLIC, anon, authenticated, service_role;

-- One serialized device request is one statement from Data API. Locking the
-- assignment makes repeated keys and the 30-second device rate limit atomic.
CREATE FUNCTION kof5.synthetic_alert_create(
    p_patient_id uuid, p_risk_category text, p_idempotency_key uuid
) RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_device uuid := auth.uid();
    v_encounter uuid;
    v_existing kof5.synthetic_aux_alert%ROWTYPE;
    v_alert_id uuid;
BEGIN
    IF v_device IS NULL OR p_idempotency_key IS NULL
       OR p_patient_id IS DISTINCT FROM '00000000-0000-4000-8000-000000000975'::uuid
       OR p_risk_category IS NULL OR p_risk_category NOT IN (
           'breathing', 'chest_pain', 'fall', 'pain', 'dizziness', 'distress'
       ) OR NOT COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
       OR NOT kof5.anonymous_auth_user(v_device) THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    SELECT d.encounter_id INTO v_encounter
    FROM kof5.patient_device_assignment d
    WHERE d.device_user_id = v_device AND d.patient_id = p_patient_id
      AND d.status = 'active' AND d.paired_at <= now()
      AND d.revoked_at IS NULL AND d.expires_at > now()
      AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
    FOR UPDATE;
    IF v_encounter IS NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    SELECT a.* INTO v_existing FROM kof5.synthetic_aux_alert a
    WHERE a.device_user_id = v_device AND a.idempotency_key = p_idempotency_key;
    IF FOUND THEN
        IF v_existing.patient_id = p_patient_id
           AND v_existing.encounter_id = v_encounter
           AND v_existing.risk_category = p_risk_category THEN
            RETURN QUERY SELECT true, v_existing.alert_id, v_existing.state;
        ELSE
            RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        END IF;
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM kof5.synthetic_aux_alert a
               WHERE a.device_user_id = v_device
                 AND a.created_at > now() - interval '30 seconds') THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    INSERT INTO kof5.synthetic_aux_alert (
        patient_id, encounter_id, device_user_id, idempotency_key, risk_category
    ) VALUES (p_patient_id, v_encounter, v_device, p_idempotency_key, p_risk_category)
    RETURNING kof5.synthetic_aux_alert.alert_id INTO v_alert_id;
    INSERT INTO kof5.safety_audit_event (patient_id, event_type)
    VALUES (p_patient_id, 'high_risk_utterance_detected'),
           (p_patient_id, 'alert_created');
    RETURN QUERY SELECT true, v_alert_id, 'created'::text;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_create(uuid, text, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_alert_create(uuid, text, uuid)
    TO authenticated;
CREATE FUNCTION api.synthetic_alert_create(
    p_patient_id uuid, p_risk_category text, p_idempotency_key uuid
) RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_create(p_patient_id, p_risk_category, p_idempotency_key);
$$;
REVOKE ALL ON FUNCTION api.synthetic_alert_create(uuid, text, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_alert_create(uuid, text, uuid) TO authenticated;

-- Timeouts are synthetic DB state, calculated only when an assigned staff
-- lists or acts; no scheduled clinical escalation or external delivery exists.
CREATE FUNCTION kof5.synthetic_alert_apply_timeouts() RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_count integer;
BEGIN
    WITH expired AS (
        UPDATE kof5.synthetic_aux_alert a
        SET state = 'failed', failed_at = now(),
            failure_reason = CASE WHEN a.state = 'created'
                THEN 'delivery_timeout' ELSE 'ack_timeout' END
        WHERE a.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
          AND ((a.state = 'created' AND a.created_at <= now() - interval '60 seconds')
            OR (a.state = 'delivered'
                AND a.delivered_at <= now() - interval '5 minutes'))
        RETURNING a.patient_id
    )
    INSERT INTO kof5.safety_audit_event (patient_id, event_type)
    SELECT patient_id, 'alert_failed' FROM expired;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_apply_timeouts()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION kof5.synthetic_alert_staff_ready()
RETURNS TABLE (ready boolean, patient_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT kof5.synthetic_assigned_care_staff(
               '00000000-0000-4000-8000-000000000975'::uuid) AS ready,
           CASE WHEN kof5.synthetic_assigned_care_staff(
               '00000000-0000-4000-8000-000000000975'::uuid)
               THEN '00000000-0000-4000-8000-000000000975'::uuid
               ELSE NULL::uuid END AS patient_id;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_staff_ready()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_alert_staff_ready() TO authenticated;
CREATE FUNCTION api.synthetic_alert_staff_ready()
RETURNS TABLE (ready boolean, patient_id uuid)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_staff_ready();
$$;
REVOKE ALL ON FUNCTION api.synthetic_alert_staff_ready()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_alert_staff_ready() TO authenticated;

CREATE FUNCTION kof5.synthetic_alert_staff_list()
RETURNS TABLE (
    alert_id uuid, patient_id uuid, encounter_id uuid, risk_category text,
    state text, created_at timestamptz, delivered_at timestamptz,
    acknowledged_at timestamptz, resolved_at timestamptz, failed_at timestamptz,
    failure_reason text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NOT kof5.synthetic_assigned_care_staff(
        '00000000-0000-4000-8000-000000000975'::uuid) THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT a.alert_id, a.patient_id, a.encounter_id,
        a.risk_category, a.state, a.created_at, a.delivered_at,
        a.acknowledged_at, a.resolved_at, a.failed_at, a.failure_reason
    FROM kof5.synthetic_aux_alert a
    WHERE a.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ORDER BY a.created_at DESC, a.alert_id LIMIT 20;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_staff_list()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_alert_staff_list() TO authenticated;
CREATE FUNCTION api.synthetic_alert_staff_list()
RETURNS TABLE (
    alert_id uuid, patient_id uuid, encounter_id uuid, risk_category text,
    state text, created_at timestamptz, delivered_at timestamptz,
    acknowledged_at timestamptz, resolved_at timestamptz, failed_at timestamptz,
    failure_reason text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_staff_list();
$$;
REVOKE ALL ON FUNCTION api.synthetic_alert_staff_list()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_alert_staff_list() TO authenticated;

CREATE FUNCTION kof5.synthetic_alert_timeout_sweep()
RETURNS TABLE (authorized boolean, failed_count integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NOT kof5.synthetic_assigned_care_staff(
        '00000000-0000-4000-8000-000000000975'::uuid) THEN
        RETURN QUERY SELECT false, 0;
        RETURN;
    END IF;
    RETURN QUERY SELECT true, kof5.synthetic_alert_apply_timeouts();
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_timeout_sweep()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_alert_timeout_sweep() TO authenticated;
CREATE FUNCTION api.synthetic_alert_timeout_sweep()
RETURNS TABLE (authorized boolean, failed_count integer)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_timeout_sweep();
$$;
REVOKE ALL ON FUNCTION api.synthetic_alert_timeout_sweep()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_alert_timeout_sweep() TO authenticated;

CREATE FUNCTION kof5.synthetic_alert_staff_transition(p_alert_id uuid, p_action text)
RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_alert_id uuid;
    v_state text;
    v_event text;
BEGIN
    IF p_alert_id IS NULL OR p_action IS NULL
       OR p_action NOT IN ('dashboard_receipt', 'ack', 'resolve')
       OR NOT kof5.synthetic_assigned_care_staff(
           '00000000-0000-4000-8000-000000000975'::uuid) THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    PERFORM kof5.synthetic_alert_apply_timeouts();
    IF p_action = 'dashboard_receipt' THEN
        UPDATE kof5.synthetic_aux_alert a
        SET state = 'delivered', delivered_at = now(),
            delivered_by_auth_user_id = auth.uid()
        WHERE a.alert_id = p_alert_id AND a.state = 'created'
          AND a.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        RETURNING a.alert_id, a.state INTO v_alert_id, v_state;
        v_event := 'alert_delivered';
    ELSIF p_action = 'ack' THEN
        UPDATE kof5.synthetic_aux_alert a
        SET state = 'acknowledged', acknowledged_at = now(),
            acknowledged_by_auth_user_id = auth.uid()
        WHERE a.alert_id = p_alert_id AND a.state = 'delivered'
          AND a.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        RETURNING a.alert_id, a.state INTO v_alert_id, v_state;
        v_event := 'alert_acknowledged';
    ELSE
        UPDATE kof5.synthetic_aux_alert a
        SET state = 'resolved', resolved_at = now(),
            resolved_by_auth_user_id = auth.uid()
        WHERE a.alert_id = p_alert_id AND a.state = 'acknowledged'
          AND a.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        RETURNING a.alert_id, a.state INTO v_alert_id, v_state;
        v_event := 'alert_resolved';
    END IF;
    IF v_alert_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    INSERT INTO kof5.safety_audit_event (patient_id, event_type)
    VALUES ('00000000-0000-4000-8000-000000000975'::uuid, v_event);
    RETURN QUERY SELECT true, v_alert_id, v_state;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_alert_staff_transition(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_alert_staff_transition(uuid, text)
    TO authenticated;

CREATE FUNCTION api.synthetic_alert_dashboard_receipt(p_alert_id uuid)
RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_staff_transition(p_alert_id, 'dashboard_receipt');
$$;
CREATE FUNCTION api.synthetic_alert_ack(p_alert_id uuid)
RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_staff_transition(p_alert_id, 'ack');
$$;
CREATE FUNCTION api.synthetic_alert_resolve(p_alert_id uuid)
RETURNS TABLE (authorized boolean, alert_id uuid, state text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_alert_staff_transition(p_alert_id, 'resolve');
$$;
REVOKE ALL ON FUNCTION api.synthetic_alert_dashboard_receipt(uuid),
    api.synthetic_alert_ack(uuid), api.synthetic_alert_resolve(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_alert_dashboard_receipt(uuid),
    api.synthetic_alert_ack(uuid), api.synthetic_alert_resolve(uuid)
    TO authenticated;
