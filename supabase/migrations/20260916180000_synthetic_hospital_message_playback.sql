-- Synthetic patient975 only. A receipt records a device's claim that native
-- playback completed. It is not proof of hearing, comprehension or delivery.
ALTER TABLE kof5.hospital_message
    ADD COLUMN delivered_by_device_user_id uuid
        REFERENCES auth.users (id) ON DELETE RESTRICT,
    ADD COLUMN playback_attempt_id uuid;
ALTER TABLE kof5.hospital_message
    ADD CONSTRAINT synthetic_playback_receipt_complete CHECK (
        patient_id <> '00000000-0000-4000-8000-000000000975'::uuid
        OR delivery_status <> 'delivered'
        OR (delivered_by_device_user_id IS NOT NULL
            AND playback_attempt_id IS NOT NULL
            AND substring(playback_attempt_id::text, 15, 1) = '4'
            AND substring(playback_attempt_id::text, 20, 1) IN ('8','9','a','b'))
    );
ALTER TABLE kof5.hospital_message
    ADD CONSTRAINT synthetic_playback_receipt_pending_empty CHECK (
        patient_id <> '00000000-0000-4000-8000-000000000975'::uuid
        OR delivery_status <> 'pending'
        OR (delivered_by_device_user_id IS NULL
            AND playback_attempt_id IS NULL)
    );

-- All clinical prerequisites are rechecked here; a prior due-message fetch is
-- never sufficient. The current admission and post-admission dissent are
-- explicit because the older device_trial_ready helper has no dissent check.
CREATE FUNCTION kof5.synthetic_playback_device_current(
    _patient_id uuid, _encounter_id uuid, _device_user_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT _patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND kof5.anonymous_auth_user(_device_user_id)
       AND EXISTS (
           SELECT 1 FROM kof5.patient_device_assignment d
           JOIN kof5.hospital_encounter e
             ON e.encounter_id = d.encounter_id AND e.patient_id = d.patient_id
           JOIN kof5.hospital_patient p ON p.patient_id = d.patient_id
           WHERE d.device_user_id = _device_user_id
             AND d.patient_id = _patient_id AND d.encounter_id = _encounter_id
             AND d.status = 'active' AND d.revoked_at IS NULL
             AND d.paired_at <= now() AND d.expires_at > now()
             AND p.active AND e.status = 'in_progress'
             AND e.admitted_at <= now() AND e.discharged_at IS NULL
             AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
             AND NOT EXISTS (
                 SELECT 1 FROM kof5.safety_audit_event a
                 WHERE a.patient_id = d.patient_id
                   AND a.event_type = 'patient_dissent'
                   AND a.occurred_at >= e.admitted_at
             )
       );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_playback_device_current(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_playback_device_current(uuid, uuid, uuid)
    TO authenticated;

-- Only an approved two-staff draft can be completed, preserving its exact
-- original text, approver, approval time and requested schedule.
CREATE FUNCTION kof5.synthetic_playback_approved_origin(_message_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM kof5.hospital_message m
        JOIN kof5.synthetic_hospital_message_draft d
          ON d.draft_id = m.message_id
        WHERE m.message_id = _message_id
          AND m.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
          AND d.patient_id = m.patient_id AND d.encounter_id = m.encounter_id
          AND d.status = 'approved' AND d.approved_at = m.approved_at
          AND d.approved_by_auth_user_id::text = m.approved_by_staff_ref
          AND d.proposed_text = m.approved_text
          AND m.due_at = CASE WHEN d.schedule_mode = 'now'
                  THEN d.approved_at ELSE d.requested_due_at END
    );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_playback_approved_origin(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_playback_approved_origin(uuid)
    TO authenticated;

CREATE FUNCTION kof5.guard_synthetic_playback_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF OLD.patient_id <> '00000000-0000-4000-8000-000000000975'::uuid THEN
        RETURN NEW;
    END IF;
    IF OLD.delivery_status <> 'pending' OR NEW.delivery_status <> 'delivered'
       OR NEW.message_id IS DISTINCT FROM OLD.message_id
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id
       OR NEW.approved_text IS DISTINCT FROM OLD.approved_text
       OR NEW.approved_by_staff_ref IS DISTINCT FROM OLD.approved_by_staff_ref
       OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
       OR NEW.due_at IS DISTINCT FROM OLD.due_at
       OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
       OR NEW.playback_attempt_id IS NULL
       OR substring(NEW.playback_attempt_id::text, 15, 1) <> '4'
       OR substring(NEW.playback_attempt_id::text, 20, 1) NOT IN ('8','9','a','b') THEN
        RAISE EXCEPTION 'synthetic playback receipt requires pending approved message'
            USING ERRCODE = '23514';
    END IF;
    NEW.delivered_at := now();
    NEW.delivered_by_device_user_id := auth.uid();
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION kof5.guard_synthetic_playback_receipt()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_message_playback_receipt
    BEFORE UPDATE OF delivery_status, delivered_at,
        delivered_by_device_user_id, playback_attempt_id
    ON kof5.hospital_message FOR EACH ROW
    EXECUTE FUNCTION kof5.guard_synthetic_playback_receipt();

GRANT UPDATE (delivery_status, delivered_at,
    delivered_by_device_user_id, playback_attempt_id)
    ON kof5.hospital_message TO authenticated;
CREATE POLICY synthetic_playback_device_complete
    ON kof5.hospital_message FOR UPDATE TO authenticated
    USING (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        AND delivery_status = 'pending' AND due_at <= now()
        AND kof5.synthetic_playback_approved_origin(message_id)
        AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND kof5.synthetic_playback_device_current(
            patient_id, encounter_id, (SELECT auth.uid()))
    )
    WITH CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        AND delivery_status = 'delivered'
        AND delivered_by_device_user_id = (SELECT auth.uid())
        AND playback_attempt_id IS NOT NULL
        AND substring(playback_attempt_id::text, 15, 1) = '4'
            AND substring(playback_attempt_id::text, 20, 1) IN ('8','9','a','b')
        AND kof5.synthetic_playback_approved_origin(message_id)
        AND kof5.synthetic_playback_device_current(
            patient_id, encounter_id, (SELECT auth.uid()))
    );

-- PostgreSQL evaluates SELECT visibility of an UPDATE result. Extend the
-- existing single device SELECT policy to its own current receipt row;
-- staff/guardian list views still require hospital_patient staff RLS.
ALTER POLICY synthetic_due_message_device_read ON kof5.hospital_message
    USING (
        (
            patient_id = '00000000-0000-4000-8000-000000000975'::uuid
            AND delivery_status = 'pending' AND due_at <= now()
            AND kof5.device_trial_ready(patient_id, encounter_id)
            AND EXISTS (
                SELECT 1 FROM kof5.patient_device_assignment d
                WHERE d.device_user_id = (SELECT auth.uid())
                  AND d.patient_id = hospital_message.patient_id
                  AND d.encounter_id = hospital_message.encounter_id
            )
        ) OR (
            patient_id = '00000000-0000-4000-8000-000000000975'::uuid
            AND delivery_status = 'delivered'
            AND delivered_by_device_user_id = (SELECT auth.uid())
            AND playback_attempt_id IS NOT NULL
            AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
            AND kof5.synthetic_playback_approved_origin(message_id)
            AND kof5.synthetic_playback_device_current(
                patient_id, encounter_id, (SELECT auth.uid()))
        )
    );

CREATE FUNCTION kof5.same_synthetic_playback_attempt(
    _patient_id uuid, _message_id uuid, _attempt_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM kof5.hospital_message m
        WHERE m.patient_id = _patient_id AND m.message_id = _message_id
          AND m.delivery_status = 'delivered'
          AND m.delivered_by_device_user_id = auth.uid()
          AND m.playback_attempt_id = _attempt_id
          AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
          AND kof5.synthetic_playback_approved_origin(m.message_id)
          AND kof5.synthetic_playback_device_current(
              m.patient_id, m.encounter_id, m.delivered_by_device_user_id)
    );
$$;
REVOKE ALL ON FUNCTION kof5.same_synthetic_playback_attempt(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.same_synthetic_playback_attempt(uuid, uuid, uuid)
    TO authenticated;

-- Scalar boolean; a false/HTTP failure must never be interpreted as delivered.
CREATE FUNCTION api.synthetic_hospital_message_playback_complete(
    p_patient_id uuid, p_message_id uuid, p_attempt_id uuid
) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = '' AS $$
DECLARE changed_count integer;
BEGIN
    IF p_patient_id IS DISTINCT FROM
            '00000000-0000-4000-8000-000000000975'::uuid
       OR p_message_id IS NULL OR p_attempt_id IS NULL
       OR substring(p_attempt_id::text, 15, 1) <> '4'
       OR substring(p_attempt_id::text, 20, 1) NOT IN ('8','9','a','b') THEN
        RETURN false;
    END IF;
    UPDATE kof5.hospital_message m
    SET delivery_status = 'delivered', delivered_at = now(),
        delivered_by_device_user_id = auth.uid(),
        playback_attempt_id = p_attempt_id
    WHERE m.message_id = p_message_id AND m.patient_id = p_patient_id
      AND m.delivery_status = 'pending' AND m.due_at <= now()
      AND kof5.synthetic_playback_approved_origin(m.message_id)
      AND EXISTS (
          SELECT 1 FROM api.patient_device_context d
          WHERE d.patient_id = m.patient_id
            AND d.encounter_id = m.encounter_id
      )
      AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
      AND kof5.synthetic_playback_device_current(
          m.patient_id, m.encounter_id, auth.uid());
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    IF changed_count = 1 THEN
        RETURN true;
    END IF;
    RETURN kof5.same_synthetic_playback_attempt(
        p_patient_id, p_message_id, p_attempt_id);
END;
$$;
REVOKE ALL ON FUNCTION api.synthetic_hospital_message_playback_complete(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_hospital_message_playback_complete(uuid, uuid, uuid)
    TO authenticated;
