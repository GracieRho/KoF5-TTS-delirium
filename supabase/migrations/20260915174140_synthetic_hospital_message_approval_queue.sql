-- Synthetic fixture only: two separate assigned permanent care_staff accounts
-- propose and approve an exact hospital message. Approval enqueues a pending
-- current-encounter message; no TTS delivery/acknowledgement occurs here.

CREATE TABLE kof5.synthetic_hospital_message_draft (
    draft_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL,
    encounter_id uuid NOT NULL,
    proposed_text text NOT NULL CHECK (
        length(trim(proposed_text)) > 0 AND length(proposed_text) <= 200
    ),
    schedule_mode text NOT NULL CHECK (schedule_mode IN ('now', 'scheduled')),
    requested_due_at timestamptz,
    proposed_by_auth_user_id uuid NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE RESTRICT,
    proposed_at timestamptz NOT NULL DEFAULT now(),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved')),
    approved_by_auth_user_id uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
    approved_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK ((schedule_mode = 'now' AND requested_due_at IS NULL)
        OR (schedule_mode = 'scheduled' AND requested_due_at IS NOT NULL)),
    CHECK (schedule_mode <> 'scheduled' OR requested_due_at > proposed_at),
    CHECK ((status = 'approved') = (approved_at IS NOT NULL)),
    CHECK ((status = 'approved') = (approved_by_auth_user_id IS NOT NULL)),
    CHECK (approved_by_auth_user_id IS NULL
        OR approved_by_auth_user_id <> proposed_by_auth_user_id)
);
CREATE INDEX synthetic_hospital_message_draft_patient_idx
    ON kof5.synthetic_hospital_message_draft (patient_id, encounter_id, status, proposed_at);
ALTER TABLE kof5.synthetic_hospital_message_draft ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_hospital_message_draft FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_hospital_message_draft
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (patient_id, encounter_id, proposed_text, schedule_mode, requested_due_at),
    UPDATE (status) ON kof5.synthetic_hospital_message_draft TO authenticated;

-- Reuse the same pinned fixture/current encounter/three-consent/voice-profile
-- readiness that requires a verified assigned permanent care_staff account.
CREATE POLICY synthetic_message_staff_read ON kof5.synthetic_hospital_message_draft
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM api.synthetic_device_pairing_ready r
        WHERE r.patient_id = synthetic_hospital_message_draft.patient_id
          AND r.encounter_id = synthetic_hospital_message_draft.encounter_id
    ));
CREATE POLICY synthetic_message_staff_propose ON kof5.synthetic_hospital_message_draft
    FOR INSERT TO authenticated
    WITH CHECK (
        status = 'draft' AND approved_at IS NULL
        AND approved_by_auth_user_id IS NULL
        AND proposed_by_auth_user_id = (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_message_draft.patient_id
              AND r.encounter_id = synthetic_hospital_message_draft.encounter_id
        )
    );
CREATE POLICY synthetic_message_distinct_staff_approve ON kof5.synthetic_hospital_message_draft
    FOR UPDATE TO authenticated
    USING (
        status = 'draft' AND proposed_by_auth_user_id <> (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_message_draft.patient_id
              AND r.encounter_id = synthetic_hospital_message_draft.encounter_id
        )
    )
    WITH CHECK (
        status = 'approved' AND approved_by_auth_user_id = (SELECT auth.uid())
        AND approved_at IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_message_draft.patient_id
              AND r.encounter_id = synthetic_hospital_message_draft.encounter_id
        )
    );

CREATE FUNCTION kof5.prepare_synthetic_hospital_message_approval() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF OLD.status <> 'draft' OR NEW.status <> 'approved'
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id
       OR NEW.proposed_text IS DISTINCT FROM OLD.proposed_text
       OR NEW.schedule_mode IS DISTINCT FROM OLD.schedule_mode
       OR NEW.requested_due_at IS DISTINCT FROM OLD.requested_due_at
       OR NEW.proposed_by_auth_user_id IS DISTINCT FROM OLD.proposed_by_auth_user_id
       OR NEW.proposed_at IS DISTINCT FROM OLD.proposed_at THEN
        RAISE EXCEPTION 'synthetic hospital approval may only change draft status'
            USING ERRCODE = '23514';
    END IF;
    IF OLD.proposed_by_auth_user_id = auth.uid() THEN
        RAISE EXCEPTION 'synthetic hospital message needs a separate approver'
            USING ERRCODE = '42501';
    END IF;
    IF OLD.schedule_mode = 'scheduled' AND OLD.requested_due_at <= now() THEN
        RAISE EXCEPTION 'scheduled time passed before approval'
            USING ERRCODE = '23514';
    END IF;
    NEW.approved_by_auth_user_id := auth.uid();
    NEW.approved_at := now();
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.prepare_synthetic_hospital_message_approval()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_message_prepare_approval
    BEFORE UPDATE OF status ON kof5.synthetic_hospital_message_draft
    FOR EACH ROW EXECUTE FUNCTION kof5.prepare_synthetic_hospital_message_approval();

CREATE FUNCTION kof5.enqueue_approved_synthetic_hospital_message() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO kof5.hospital_message (
        message_id, patient_id, encounter_id, approved_text,
        approved_by_staff_ref, approved_at, due_at
    ) VALUES (
        NEW.draft_id, NEW.patient_id, NEW.encounter_id, NEW.proposed_text,
        NEW.approved_by_auth_user_id::text, NEW.approved_at,
        CASE WHEN NEW.schedule_mode = 'now' THEN NEW.approved_at ELSE NEW.requested_due_at END
    );
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.enqueue_approved_synthetic_hospital_message()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_message_enqueue
    AFTER UPDATE OF status ON kof5.synthetic_hospital_message_draft
    FOR EACH ROW WHEN (NEW.status = 'approved')
    EXECUTE FUNCTION kof5.enqueue_approved_synthetic_hospital_message();

CREATE VIEW api.synthetic_hospital_message_draft WITH (security_invoker = true) AS
    SELECT draft_id, patient_id, encounter_id, proposed_text, schedule_mode,
           requested_due_at, proposed_by_auth_user_id, proposed_at, status,
           approved_by_auth_user_id, approved_at
    FROM kof5.synthetic_hospital_message_draft;
REVOKE ALL ON api.synthetic_hospital_message_draft
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (patient_id, encounter_id, proposed_text, schedule_mode, requested_due_at),
    UPDATE (status) ON api.synthetic_hospital_message_draft TO authenticated;

-- A misissued verified staff membership must never turn an anonymous Auth
-- device into a staff account. Protect the shared patient/encounter/message
-- read root, while the narrowly scoped due-message device policy below remains.
ALTER POLICY hospital_patient_verified_staff_read ON kof5.hospital_patient
    USING (
        NOT kof5.anonymous_auth_user((SELECT auth.uid()))
        AND (
            EXISTS (
                SELECT 1 FROM kof5.hospital_staff_membership m
                WHERE m.auth_user_id = (SELECT auth.uid())
                  AND m.hospital_ref = hospital_patient.hospital_ref
                  AND m.product_role = 'registrar' AND m.status = 'verified'
                  AND m.effective_at <= now()
                  AND (m.expires_at IS NULL OR m.expires_at > now())
            ) OR EXISTS (
                SELECT 1 FROM kof5.hospital_staff_assignment a
                JOIN kof5.hospital_staff_membership m ON m.membership_id = a.membership_id
                WHERE a.patient_id = hospital_patient.patient_id
                  AND a.hospital_ref = hospital_patient.hospital_ref
                  AND a.status = 'verified' AND a.effective_at <= now()
                  AND (a.expires_at IS NULL OR a.expires_at > now())
                  AND m.auth_user_id = (SELECT auth.uid())
                  AND m.product_role = 'care_staff' AND m.status = 'verified'
                  AND m.effective_at <= now()
                  AND (m.expires_at IS NULL OR m.expires_at > now())
            )
        )
    );

-- Anonymous paired device can read only exact, pending, due approved messages.
-- Its assignment SELECT policy checks expiry, current encounter and consent.
CREATE POLICY synthetic_due_message_device_read ON kof5.hospital_message
    FOR SELECT TO authenticated
    USING (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        AND delivery_status = 'pending' AND due_at <= now()
        AND kof5.device_trial_ready(patient_id, encounter_id)
        AND EXISTS (
            SELECT 1 FROM kof5.patient_device_assignment d
            WHERE d.device_user_id = (SELECT auth.uid())
              AND d.patient_id = hospital_message.patient_id
              AND d.encounter_id = hospital_message.encounter_id
        )
    );

-- Bounded discovery: IDs only, maximum three records. Each invocation uses
-- current assignment/consent/message RLS in this single SELECT statement.
CREATE FUNCTION api.synthetic_due_hospital_message_ids(_patient_id uuid)
RETURNS TABLE (message_id uuid, due_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT m.message_id, m.due_at
    FROM kof5.patient_device_assignment d
    JOIN kof5.hospital_message m
      ON m.patient_id = d.patient_id AND m.encounter_id = d.encounter_id
    WHERE d.device_user_id = (SELECT auth.uid())
      AND d.patient_id = _patient_id
      AND _patient_id = '00000000-0000-4000-8000-000000000975'::uuid
      AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
      AND m.delivery_status = 'pending' AND m.due_at <= now()
    ORDER BY m.due_at, m.message_id
    LIMIT 3;
$$;
REVOKE ALL ON FUNCTION api.synthetic_due_hospital_message_ids(uuid)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_due_hospital_message_ids(uuid) TO authenticated;

-- Per-ID atomic recheck. A denied/not-yet-due/nonexistent message yields a
-- single false/null row; this does not mark delivered or acknowledged.
CREATE FUNCTION api.synthetic_due_hospital_message(_patient_id uuid, _message_id uuid)
RETURNS TABLE (authorized boolean, message_id uuid, approved_text text, due_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    WITH eligible AS (
        SELECT d.patient_id, d.encounter_id
        FROM kof5.patient_device_assignment d
        WHERE d.device_user_id = (SELECT auth.uid())
          AND d.patient_id = _patient_id
          AND _patient_id = '00000000-0000-4000-8000-000000000975'::uuid
          AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
    ), picked AS (
        SELECT m.message_id, m.approved_text, m.due_at
        FROM eligible d
        JOIN kof5.hospital_message m
          ON m.patient_id = d.patient_id AND m.encounter_id = d.encounter_id
        WHERE m.message_id = _message_id
          AND m.delivery_status = 'pending' AND m.due_at <= now()
    )
    SELECT p.message_id IS NOT NULL, p.message_id, p.approved_text, p.due_at
    FROM (SELECT 1) one LEFT JOIN picked p ON true;
$$;
REVOKE ALL ON FUNCTION api.synthetic_due_hospital_message(uuid, uuid)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_due_hospital_message(uuid, uuid) TO authenticated;
