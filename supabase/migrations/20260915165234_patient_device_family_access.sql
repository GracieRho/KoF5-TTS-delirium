-- Anonymous Auth users are authenticated role, so device access must bind to
-- a private assignment and current trial prerequisites. This is synthetic
-- readiness only; institution identity/alert workflows still block patients.
-- A pinned synthetic fixture is the sole eligible patient, with no switch to
-- activate real IDs until those workflows are approved and implemented.
CREATE TABLE kof5.patient_device_assignment (
    device_user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE RESTRICT,
    patient_id uuid NOT NULL,
    encounter_id uuid NOT NULL,
    paired_by_staff_user_id uuid NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    paired_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    FOREIGN KEY (encounter_id, patient_id)
        REFERENCES kof5.hospital_encounter (encounter_id, patient_id),
    CHECK (expires_at > paired_at AND expires_at <= paired_at + interval '8 hours'),
    CHECK (status <> 'revoked' OR revoked_at IS NOT NULL)
);
CREATE FUNCTION kof5.guard_device_assignment_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NEW.device_user_id IS DISTINCT FROM OLD.device_user_id
       OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id THEN
        RAISE EXCEPTION 'device binding is immutable' USING ERRCODE = '23514';
    END IF;
    IF OLD.status = 'revoked' AND NEW.status <> 'revoked' THEN
        RAISE EXCEPTION 'revoked device requires new Auth user and pairing'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION kof5.guard_device_assignment_update()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER device_assignment_terminal_binding
    BEFORE UPDATE ON kof5.patient_device_assignment
    FOR EACH ROW EXECUTE FUNCTION kof5.guard_device_assignment_update();
ALTER TABLE kof5.patient_device_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.patient_device_assignment FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.patient_device_assignment
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT (device_user_id, patient_id, encounter_id, expires_at)
    ON kof5.patient_device_assignment TO authenticated;

-- Private boolean helpers inspect tables unavailable to the patient client.
-- They expose no patient data and are outside the Data API schema.
CREATE FUNCTION kof5.anonymous_auth_user(_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (SELECT 1 FROM auth.users u
                   WHERE u.id = _user_id AND u.is_anonymous IS TRUE);
$$;
CREATE FUNCTION kof5.device_trial_ready(_patient_id uuid, _encounter_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT _patient_id = '00000000-0000-4000-8000-000000000975'::uuid
       AND EXISTS (
        SELECT 1 FROM kof5.voice_profile_with_trial_consents v
        WHERE v.patient_id = _patient_id AND v.encounter_id = _encounter_id
    );
$$;
REVOKE ALL ON FUNCTION kof5.anonymous_auth_user(uuid),
    kof5.device_trial_ready(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.anonymous_auth_user(uuid),
    kof5.device_trial_ready(uuid, uuid) TO authenticated;

CREATE POLICY device_own_current_assignment_read
    ON kof5.patient_device_assignment FOR SELECT TO authenticated
    USING (
        device_user_id = (SELECT auth.uid())
        AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND kof5.anonymous_auth_user(device_user_id)
        AND status = 'active' AND paired_at <= now()
        AND revoked_at IS NULL AND expires_at > now()
        AND kof5.device_trial_ready(patient_id, encounter_id)
    );

CREATE POLICY verified_assigned_staff_device_pair
    ON kof5.patient_device_assignment FOR INSERT TO authenticated
    WITH CHECK (
        paired_by_staff_user_id = (SELECT auth.uid())
        AND NOT COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, true)
        AND NOT kof5.anonymous_auth_user(paired_by_staff_user_id)
        AND kof5.anonymous_auth_user(device_user_id)
        AND status = 'active' AND paired_at <= now() AND revoked_at IS NULL
        AND kof5.device_trial_ready(patient_id, encounter_id)
        AND EXISTS (
            SELECT 1 FROM kof5.hospital_staff_assignment a
            JOIN kof5.hospital_staff_membership m
              ON m.membership_id = a.membership_id
            WHERE a.patient_id = patient_device_assignment.patient_id
              AND a.status = 'verified' AND a.effective_at <= now()
              AND (a.expires_at IS NULL OR a.expires_at > now())
              AND m.auth_user_id = (SELECT auth.uid())
              AND m.hospital_ref = a.hospital_ref
              AND m.product_role = 'care_staff' AND m.status = 'verified'
              AND m.effective_at <= now()
              AND (m.expires_at IS NULL OR m.expires_at > now())
        )
    );

CREATE VIEW api.patient_device_pairing WITH (security_invoker = true) AS
    SELECT device_user_id, patient_id, encounter_id, expires_at
    FROM kof5.patient_device_assignment;
REVOKE ALL ON api.patient_device_pairing
    FROM PUBLIC, anon, authenticated, service_role;
GRANT INSERT ON api.patient_device_pairing TO authenticated;

CREATE VIEW api.synthetic_device_pairing_ready WITH (security_invoker = true) AS
    SELECT DISTINCT a.patient_id, e.encounter_id
    FROM kof5.hospital_staff_assignment a
    JOIN kof5.hospital_staff_membership m ON m.membership_id = a.membership_id
    JOIN kof5.hospital_encounter e ON e.patient_id = a.patient_id
    WHERE m.auth_user_id = (SELECT auth.uid())
      AND NOT COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, true)
      AND NOT kof5.anonymous_auth_user(m.auth_user_id)
      AND m.hospital_ref = a.hospital_ref
      AND m.product_role = 'care_staff' AND m.status = 'verified'
      AND m.effective_at <= now()
      AND (m.expires_at IS NULL OR m.expires_at > now())
      AND a.status = 'verified' AND a.effective_at <= now()
      AND (a.expires_at IS NULL OR a.expires_at > now())
      AND kof5.device_trial_ready(a.patient_id, e.encounter_id);
REVOKE ALL ON api.synthetic_device_pairing_ready
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON api.synthetic_device_pairing_ready TO authenticated;

CREATE VIEW api.patient_device_context WITH (security_invoker = true) AS
    SELECT patient_id, encounter_id FROM kof5.patient_device_assignment;
REVOKE ALL ON api.patient_device_context
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON api.patient_device_context TO authenticated;

-- RLS on family_fact must include the device, but the guardian edit view must
-- stay guardian-only or a device could list facts outside the bounded RPC.
CREATE FUNCTION kof5.device_guardian_fact_ready(
    _patient_id uuid, _guardian_user_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
       AND kof5.anonymous_auth_user(auth.uid())
       AND EXISTS (
           SELECT 1 FROM kof5.patient_device_assignment d
           WHERE d.device_user_id = auth.uid() AND d.patient_id = _patient_id
             AND d.status = 'active' AND d.paired_at <= now()
             AND d.revoked_at IS NULL AND d.expires_at > now()
             AND kof5.device_trial_ready(d.patient_id, d.encounter_id)
       )
       AND EXISTS (
           SELECT 1 FROM kof5.patient_guardian_link l
           WHERE l.patient_id = _patient_id
             AND l.guardian_user_id = _guardian_user_id
             AND NOT kof5.anonymous_auth_user(l.guardian_user_id)
             AND l.access_status = 'verified' AND l.effective_at <= now()
             AND (l.expires_at IS NULL OR l.expires_at > now())
       );
$$;
REVOKE ALL ON FUNCTION kof5.device_guardian_fact_ready(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.device_guardian_fact_ready(uuid, uuid)
    TO authenticated;

ALTER POLICY guardian_current_family_fact_read ON kof5.family_fact
    USING (
        (author_guardian_user_id = (SELECT auth.uid()) AND EXISTS (
            SELECT 1 FROM kof5.patient_guardian_link l
            WHERE l.patient_id = family_fact.patient_id
              AND l.guardian_user_id = (SELECT auth.uid())
              AND l.access_status = 'verified' AND l.effective_at <= now()
              AND (l.expires_at IS NULL OR l.expires_at > now())
        )) OR (
            kof5.device_guardian_fact_ready(patient_id, author_guardian_user_id)
            AND active AND sensitivity = 'ordinary' AND category <> 'avoid_topic'
            AND valid_from <= now()
            AND (valid_until IS NULL OR valid_until > now())
        )
    );

-- Anonymous Auth accounts share authenticated role. A mistaken institution
-- guardian link must still not let a device create or edit family memories.
CREATE POLICY permanent_guardian_only_family_fact_insert
    ON kof5.family_fact AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (
        NOT COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND NOT kof5.anonymous_auth_user((SELECT auth.uid()))
    );
CREATE POLICY permanent_guardian_only_family_fact_update
    ON kof5.family_fact AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (
        NOT COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND NOT kof5.anonymous_auth_user((SELECT auth.uid()))
    )
    WITH CHECK (
        NOT COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND NOT kof5.anonymous_auth_user((SELECT auth.uid()))
    );

CREATE OR REPLACE VIEW api.family_context WITH (security_invoker = true) AS
    SELECT fact_id, patient_id, author_guardian_user_id, category, content,
           sensitivity, valid_from, valid_until, active, created_at
    FROM kof5.family_fact
    WHERE NOT COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
    WITH LOCAL CHECK OPTION;

CREATE OR REPLACE FUNCTION api.guardian_memory_search(p_patient_id uuid, p_term text)
RETURNS TABLE (fact_id uuid, category text, content text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT f.fact_id, f.category, f.content, f.created_at
    FROM kof5.family_fact AS f
    WHERE NOT COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
      AND NOT kof5.anonymous_auth_user(auth.uid())
      AND f.patient_id = p_patient_id
      AND f.author_guardian_user_id = (SELECT auth.uid())
      AND f.active AND f.sensitivity = 'ordinary'
      AND f.category <> 'avoid_topic'
      AND f.valid_from <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND char_length(btrim(p_term)) BETWEEN 2 AND 80
      AND position(lower(btrim(p_term)) IN lower(f.content)) > 0
    ORDER BY f.created_at DESC, f.fact_id
    LIMIT 3;
$$;

CREATE FUNCTION api.patient_family_search(p_patient_id uuid, p_term text)
RETURNS TABLE (category text, content text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT f.category, f.content
    FROM kof5.family_fact f
    WHERE p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
      AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false)
      AND EXISTS (SELECT 1 FROM api.patient_device_context d
                  WHERE d.patient_id = p_patient_id)
      AND f.patient_id = p_patient_id
      AND NOT kof5.anonymous_auth_user(f.author_guardian_user_id)
      AND f.active AND f.sensitivity = 'ordinary'
      AND f.category <> 'avoid_topic'
      AND f.valid_from <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND char_length(btrim(p_term)) BETWEEN 3 AND 500
      AND EXISTS (
          SELECT 1
          FROM regexp_split_to_table(p_term, '[^가-힣A-Za-z0-9]+') AS word(raw)
          CROSS JOIN LATERAL (
              SELECT regexp_replace(word.raw,
                  '(에서|에게|은|는|이|가|을|를|에)$', '') AS token
          ) AS term
          WHERE char_length(term.token) >= 3
            AND term.token NOT IN ('언제', '어디', '무엇', '지금', '오늘', '내일')
            AND position(lower(term.token) IN lower(f.content)) > 0
      )
    ORDER BY f.created_at DESC, f.fact_id
    LIMIT 3;
$$;
REVOKE ALL ON FUNCTION api.patient_family_search(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.patient_family_search(uuid, text) TO authenticated;
-- ponytail: lexical matching is a synthetic baseline for a few facts; add
-- semantic retrieval only after Korean misses and safety are measured.
