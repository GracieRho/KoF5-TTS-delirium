-- Fixed synthetic fixture only. Two assigned permanent care_staff accounts
-- propose and approve exact, short hospital context; real EHR writes stay shut.
ALTER TABLE kof5.hospital_context_fact
    ADD COLUMN synthetic_source_ref text
    CHECK (synthetic_source_ref IS NULL
        OR synthetic_source_ref ~ '^TEST-[A-Z0-9_-]{1,50}$');

CREATE TABLE kof5.synthetic_hospital_context_draft (
    draft_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid),
    encounter_id uuid NOT NULL,
    category text NOT NULL CHECK (category IN (
        'hospital', 'ward', 'room', 'test_schedule', 'visit_schedule')),
    proposed_text text NOT NULL CHECK (
        proposed_text = btrim(proposed_text)
        AND char_length(proposed_text) BETWEEN 1 AND 200
        AND proposed_text !~ '(진단|치료|처방|(^|[^가-힣A-Za-z0-9])약(을|은|이|물|[[:space:]])|수술|통증|증상|괜찮|위험|복용|투약)'),
    source_ref text NOT NULL CHECK (
        source_ref ~ '^TEST-[A-Z0-9_-]{1,50}$'),
    proposed_by_auth_user_id uuid NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE RESTRICT,
    proposed_at timestamptz NOT NULL DEFAULT now(),
    status text NOT NULL DEFAULT 'draft' CHECK (
        status IN ('draft', 'approved')),
    approved_by_auth_user_id uuid REFERENCES auth.users (id)
        ON DELETE RESTRICT,
    approved_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK ((status = 'approved') = (approved_at IS NOT NULL)),
    CHECK ((status = 'approved') = (approved_by_auth_user_id IS NOT NULL)),
    CHECK (approved_by_auth_user_id IS NULL
        OR approved_by_auth_user_id <> proposed_by_auth_user_id)
);
CREATE INDEX synthetic_hospital_context_draft_patient_idx
    ON kof5.synthetic_hospital_context_draft
    (patient_id, encounter_id, status, proposed_at DESC);
ALTER TABLE kof5.synthetic_hospital_context_draft ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_hospital_context_draft FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_hospital_context_draft
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (patient_id, encounter_id, category, proposed_text, source_ref),
    UPDATE (status) ON kof5.synthetic_hospital_context_draft TO authenticated;

-- The existing invoker ready view pins fixture, current encounter, verified
-- assigned permanent staff, institution gate, consents and active test profile.
CREATE POLICY synthetic_context_staff_read
    ON kof5.synthetic_hospital_context_draft FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM api.synthetic_device_pairing_ready r
        WHERE r.patient_id = synthetic_hospital_context_draft.patient_id
          AND r.encounter_id = synthetic_hospital_context_draft.encounter_id
    ));
CREATE POLICY synthetic_context_staff_propose
    ON kof5.synthetic_hospital_context_draft FOR INSERT TO authenticated
    WITH CHECK (
        status = 'draft' AND approved_at IS NULL
        AND approved_by_auth_user_id IS NULL
        AND proposed_by_auth_user_id = (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_context_draft.patient_id
              AND r.encounter_id = synthetic_hospital_context_draft.encounter_id
        )
    );
CREATE POLICY synthetic_context_distinct_staff_approve
    ON kof5.synthetic_hospital_context_draft FOR UPDATE TO authenticated
    USING (
        status = 'draft' AND proposed_by_auth_user_id <> (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_context_draft.patient_id
              AND r.encounter_id = synthetic_hospital_context_draft.encounter_id
        )
    )
    WITH CHECK (
        status = 'approved' AND approved_by_auth_user_id = (SELECT auth.uid())
        AND approved_at IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM api.synthetic_device_pairing_ready r
            WHERE r.patient_id = synthetic_hospital_context_draft.patient_id
              AND r.encounter_id = synthetic_hospital_context_draft.encounter_id
        )
    );

CREATE FUNCTION kof5.prepare_synthetic_hospital_context_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF OLD.status <> 'draft' OR NEW.status <> 'approved'
       OR NEW.draft_id IS DISTINCT FROM OLD.draft_id
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id
       OR NEW.category IS DISTINCT FROM OLD.category
       OR NEW.proposed_text IS DISTINCT FROM OLD.proposed_text
       OR NEW.source_ref IS DISTINCT FROM OLD.source_ref
       OR NEW.proposed_by_auth_user_id IS DISTINCT FROM OLD.proposed_by_auth_user_id
       OR NEW.proposed_at IS DISTINCT FROM OLD.proposed_at THEN
        RAISE EXCEPTION 'synthetic context approval may only change draft status'
            USING ERRCODE = '23514';
    END IF;
    IF OLD.proposed_by_auth_user_id = auth.uid() THEN
        RAISE EXCEPTION 'synthetic context needs a separate approver'
            USING ERRCODE = '42501';
    END IF;
    NEW.approved_by_auth_user_id := auth.uid();
    NEW.approved_at := now();
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.prepare_synthetic_hospital_context_approval()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_context_prepare_approval
    BEFORE UPDATE ON kof5.synthetic_hospital_context_draft
    FOR EACH ROW EXECUTE FUNCTION
        kof5.prepare_synthetic_hospital_context_approval();

CREATE FUNCTION kof5.publish_approved_synthetic_hospital_context()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO kof5.hospital_context_fact (
        fact_id, patient_id, encounter_id, category, content,
        source_staff_ref, synthetic_source_ref, approved_by_staff_ref,
        verified_at, valid_until, status
    ) VALUES (
        NEW.draft_id, NEW.patient_id, NEW.encounter_id, NEW.category,
        NEW.proposed_text, NEW.proposed_by_auth_user_id::text, NEW.source_ref,
        NEW.approved_by_auth_user_id::text, NEW.approved_at,
        NEW.approved_at + interval '24 hours', 'approved'
    );
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.publish_approved_synthetic_hospital_context()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_context_publish
    AFTER UPDATE OF status ON kof5.synthetic_hospital_context_draft
    FOR EACH ROW WHEN (NEW.status = 'approved')
    EXECUTE FUNCTION kof5.publish_approved_synthetic_hospital_context();

-- No app UPDATE grant exists on the approved fact, and this guard also
-- protects its content, source and attribution from privileged accidental edits.
CREATE FUNCTION kof5.keep_approved_synthetic_hospital_context()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF OLD.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND OLD.synthetic_source_ref IS NOT NULL
       AND (
           NEW.fact_id IS DISTINCT FROM OLD.fact_id
           OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
           OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id
           OR NEW.category IS DISTINCT FROM OLD.category
           OR NEW.content IS DISTINCT FROM OLD.content
           OR NEW.source_staff_ref IS DISTINCT FROM OLD.source_staff_ref
           OR NEW.synthetic_source_ref IS DISTINCT FROM OLD.synthetic_source_ref
           OR NEW.approved_by_staff_ref IS DISTINCT FROM OLD.approved_by_staff_ref
           OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
           OR NEW.valid_until IS DISTINCT FROM OLD.valid_until
       ) THEN
        RAISE EXCEPTION 'approved synthetic context and origin are immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.keep_approved_synthetic_hospital_context()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_hospital_context_approval_immutable
    BEFORE UPDATE ON kof5.hospital_context_fact FOR EACH ROW
    EXECUTE FUNCTION kof5.keep_approved_synthetic_hospital_context();

-- A denied institution/current admission closes both staff and device reads
-- of fixture facts; non-synthetic hospital records retain their prior policy.
CREATE POLICY synthetic_context_fixture_ready_read
    ON kof5.hospital_context_fact AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
        patient_id <> '00000000-0000-4000-8000-000000000975'::uuid
        OR (
            NOT kof5.anonymous_auth_user((SELECT auth.uid()))
            AND EXISTS (
                SELECT 1 FROM api.synthetic_device_pairing_ready r
                WHERE r.patient_id = hospital_context_fact.patient_id
                  AND r.encounter_id = hospital_context_fact.encounter_id
            )
        ) OR (
            COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
            AND kof5.anonymous_auth_user((SELECT auth.uid()))
            AND EXISTS (
                SELECT 1 FROM kof5.patient_device_assignment d
                WHERE d.device_user_id = (SELECT auth.uid())
                  AND d.patient_id = hospital_context_fact.patient_id
                  AND (d.encounter_id = hospital_context_fact.encounter_id
                       OR (hospital_context_fact.encounter_id IS NULL
                           AND hospital_context_fact.category = 'hospital'))
                  AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
            )
        )
    );

CREATE VIEW api.synthetic_hospital_context_draft
WITH (security_invoker = true) AS
    SELECT draft_id, patient_id, encounter_id, category, proposed_text,
           source_ref, proposed_by_auth_user_id, proposed_at, status,
           approved_by_auth_user_id, approved_at
    FROM kof5.synthetic_hospital_context_draft;
REVOKE ALL ON api.synthetic_hospital_context_draft
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (patient_id, encounter_id, category, proposed_text, source_ref),
    UPDATE (status) ON api.synthetic_hospital_context_draft TO authenticated;

-- The existing staff view gains one trailing source column. An anonymous
-- paired device may query its already permitted context rows, but never sees
-- staff proposal origin; the bounded hospital turn RPC remains unchanged.
CREATE OR REPLACE VIEW api.hospital_context_current
WITH (security_invoker = true) AS
    SELECT f.fact_id, f.patient_id, f.encounter_id, f.category, f.content,
           f.verified_at, f.valid_until,
           CASE WHEN f.patient_id =
                     '00000000-0000-4000-8000-000000000975'::uuid
                     AND NOT kof5.anonymous_auth_user((SELECT auth.uid()))
                     AND EXISTS (
                         SELECT 1 FROM api.synthetic_device_pairing_ready r
                         WHERE r.patient_id = f.patient_id
                           AND r.encounter_id = f.encounter_id
                     )
                THEN f.synthetic_source_ref ELSE NULL::text
           END AS synthetic_source_ref
    FROM kof5.hospital_context_fact f
    JOIN kof5.hospital_patient p ON p.patient_id = f.patient_id
    JOIN kof5.hospital_encounter e
      ON e.patient_id = p.patient_id AND e.status = 'in_progress'
    WHERE p.active AND f.status = 'approved' AND f.verified_at <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND (f.encounter_id = e.encounter_id
           OR (f.encounter_id IS NULL AND f.category = 'hospital'));
REVOKE ALL ON api.hospital_context_current
    FROM PUBLIC, anon, service_role;
GRANT SELECT ON api.hospital_context_current TO authenticated;
