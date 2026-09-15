-- Synthetic fixture only. The caller must have emitted a DIRECTED patient turn;
-- the database cannot identify a speaker or validate the local VAD decision.
-- No audio, ambient candidate, assistant response, or clinical transcript here.
CREATE TABLE kof5.synthetic_directed_turn (
    turn_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid),
    encounter_id uuid NOT NULL,
    device_user_id uuid NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE RESTRICT,
    client_turn_id uuid NOT NULL,
    transcript text NOT NULL CHECK (
        length(btrim(transcript)) BETWEEN 1 AND 500
        AND transcript = btrim(transcript)),
    captured_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT (
        (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') + interval '1 day')
        AT TIME ZONE 'Asia/Seoul'),
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    UNIQUE (device_user_id, client_turn_id),
    CHECK (expires_at > captured_at
        AND expires_at <= captured_at + interval '24 hours')
);
CREATE INDEX synthetic_directed_turn_today_idx
    ON kof5.synthetic_directed_turn
    (patient_id, encounter_id, captured_at DESC);
ALTER TABLE kof5.synthetic_directed_turn ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_directed_turn FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_directed_turn
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (patient_id, encounter_id, client_turn_id, transcript)
    ON kof5.synthetic_directed_turn TO authenticated;
-- An explicit trusted sweep may delete expired text. No cron is scheduled.
CREATE FUNCTION kof5.purge_expired_synthetic_directed_turns()
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE removed_count integer;
BEGIN
    DELETE FROM kof5.synthetic_directed_turn WHERE expires_at <= now();
    GET DIAGNOSTICS removed_count = ROW_COUNT;
    RETURN removed_count;
END;
$$;
REVOKE ALL ON FUNCTION kof5.purge_expired_synthetic_directed_turns()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.purge_expired_synthetic_directed_turns()
    TO service_role;

-- Private boolean helpers expose no text and are outside the Data API schema.
CREATE FUNCTION kof5.synthetic_directed_device_current(
    _patient_id uuid, _encounter_id uuid, _device_user_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT _patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND kof5.anonymous_auth_user(_device_user_id)
       AND EXISTS (
           SELECT 1 FROM kof5.patient_device_assignment d
           WHERE d.device_user_id = _device_user_id
             AND d.patient_id = _patient_id
             AND d.encounter_id = _encounter_id
             AND d.status = 'active' AND d.revoked_at IS NULL
             AND d.paired_at <= now() AND d.expires_at > now()
             AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
       );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_directed_device_current(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_directed_device_current(uuid, uuid, uuid)
    TO authenticated;

CREATE POLICY synthetic_directed_staff_today_read
    ON kof5.synthetic_directed_turn FOR SELECT TO authenticated
    USING (
        captured_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul')
            AT TIME ZONE 'Asia/Seoul')
        AND captured_at <= now() AND expires_at > now()
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_directed_turn.patient_id
              AND r.encounter_id = synthetic_directed_turn.encounter_id
        )
        AND kof5.synthetic_directed_device_current(
            patient_id, encounter_id, device_user_id)
    );
CREATE POLICY synthetic_directed_device_insert
    ON kof5.synthetic_directed_turn FOR INSERT TO authenticated
    WITH CHECK (
        device_user_id = (SELECT auth.uid())
        AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND kof5.synthetic_directed_device_current(
            patient_id, encounter_id, device_user_id)
        AND EXISTS (
            SELECT 1 FROM api.patient_device_context d
            WHERE d.patient_id = synthetic_directed_turn.patient_id
              AND d.encounter_id = synthetic_directed_turn.encounter_id
        )
    );

CREATE VIEW api.synthetic_today_transcript WITH (security_invoker = true) AS
    SELECT turn_id, patient_id, encounter_id, transcript, captured_at
    FROM kof5.synthetic_directed_turn
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'::uuid
      AND captured_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul')
          AT TIME ZONE 'Asia/Seoul')
      AND captured_at <= now() AND expires_at > now();
REVOKE ALL ON api.synthetic_today_transcript
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON api.synthetic_today_transcript TO authenticated;

CREATE FUNCTION kof5.same_synthetic_directed_replay(
    _client_turn_id uuid, _transcript text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM kof5.synthetic_directed_turn t
        WHERE t.device_user_id = auth.uid()
          AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
          AND t.client_turn_id = _client_turn_id
          AND t.transcript = _transcript
          AND t.expires_at > now()
          AND kof5.synthetic_directed_device_current(
              t.patient_id, t.encounter_id, t.device_user_id)
    );
$$;
REVOKE ALL ON FUNCTION kof5.same_synthetic_directed_replay(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.same_synthetic_directed_replay(uuid, text)
    TO authenticated;

-- Scalar JSON boolean: true for fresh write or identical current replay;
-- false for unauthorized, stale, conflicting, or malformed attempts.
CREATE FUNCTION api.record_synthetic_directed_turn(
    p_patient_id uuid, p_client_turn_id uuid, p_transcript text
) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = '' AS $$
DECLARE inserted_count integer;
DECLARE canonical_text text := btrim(p_transcript);
BEGIN
    IF p_patient_id IS DISTINCT FROM
            '00000000-0000-4000-8000-000000000975'::uuid
       OR p_client_turn_id IS NULL OR canonical_text IS NULL
       OR length(canonical_text) NOT BETWEEN 1 AND 500 THEN
        RETURN false;
    END IF;
    BEGIN
        INSERT INTO kof5.synthetic_directed_turn
            (patient_id, encounter_id, client_turn_id, transcript)
        SELECT d.patient_id, d.encounter_id, p_client_turn_id, canonical_text
        FROM api.patient_device_context d
        WHERE d.patient_id = p_patient_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN kof5.same_synthetic_directed_replay(
            p_client_turn_id, canonical_text);
    END;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 1 THEN
        RETURN true;
    END IF;
    RETURN kof5.same_synthetic_directed_replay(
        p_client_turn_id, canonical_text);
END;
$$;
REVOKE ALL ON FUNCTION api.record_synthetic_directed_turn(uuid, uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.record_synthetic_directed_turn(uuid, uuid, text)
    TO authenticated;
