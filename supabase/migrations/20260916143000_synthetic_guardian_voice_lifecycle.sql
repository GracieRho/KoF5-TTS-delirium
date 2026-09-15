-- Internal synthetic clone metadata only. The enrolled person is a permanent
-- verified guardian of fixture975; no sample audio, transcript or API key is stored.
-- Provider is a metadata slug: ElevenLabs is only the current synthetic candidate.
CREATE TABLE kof5.synthetic_guardian_voice_clone (
    clone_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ),
    guardian_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
    consent_id uuid NOT NULL,
    consent_scope text NOT NULL DEFAULT 'guardian_voice_clone'
        CHECK (consent_scope = 'guardian_voice_clone'),
    provider text NOT NULL CHECK (provider ~ '^[a-z][a-z0-9_-]{0,39}$'),
    provider_name text NOT NULL UNIQUE CHECK (
        provider_name ~ '^KoF5 internal self-voice test [0-9a-f]{32}$'
    ),
    request_key uuid NOT NULL UNIQUE,
    sample_durations_ms integer[] NOT NULL CHECK (
        cardinality(sample_durations_ms) = 3
        AND array_lower(sample_durations_ms, 1) = 1
        AND array_position(sample_durations_ms, NULL) IS NULL
        AND sample_durations_ms[1] BETWEEN 20000 AND 30000
        AND sample_durations_ms[2] BETWEEN 20000 AND 30000
        AND sample_durations_ms[3] BETWEEN 20000 AND 30000
    ),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'created', 'verification_pending',
        'deletion_pending', 'deleted', 'failed'
    )),
    voice_id text CHECK (voice_id ~ '^[A-Za-z0-9_-]{1,100}$'),
    provider_created_at timestamptz,
    verification_confirmed_at timestamptz,
    deletion_requested_at timestamptz,
    remote_absence_verified_at timestamptz,
    failure_code text CHECK (failure_code IN ('provider_rejected')),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_transition_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (consent_id, patient_id, consent_scope)
        REFERENCES kof5.consent_record (consent_id, patient_id, scope),
    UNIQUE (provider, voice_id),
    CHECK (status NOT IN ('created', 'verification_pending') OR voice_id IS NOT NULL),
    CHECK (status <> 'created' OR verification_confirmed_at IS NOT NULL),
    CHECK (status NOT IN ('deletion_pending', 'deleted')
        OR deletion_requested_at IS NOT NULL),
    CHECK ((status = 'deleted') = (remote_absence_verified_at IS NOT NULL)),
    CHECK ((status = 'failed') = (failure_code IS NOT NULL)),
    CHECK (status <> 'failed' OR voice_id IS NULL)
);
CREATE UNIQUE INDEX one_open_synthetic_guardian_clone
    ON kof5.synthetic_guardian_voice_clone (patient_id, guardian_user_id)
    WHERE status NOT IN ('deleted', 'failed');
CREATE INDEX synthetic_guardian_clone_guardian_time_idx
    ON kof5.synthetic_guardian_voice_clone (guardian_user_id, created_at DESC);
ALTER TABLE kof5.synthetic_guardian_voice_clone ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.synthetic_guardian_voice_clone FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.synthetic_guardian_voice_clone
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION kof5.guard_synthetic_guardian_clone_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.guardian_user_id IS DISTINCT FROM OLD.guardian_user_id
       OR NEW.consent_id IS DISTINCT FROM OLD.consent_id
       OR NEW.consent_scope IS DISTINCT FROM OLD.consent_scope
       OR NEW.provider IS DISTINCT FROM OLD.provider
       OR NEW.provider_name IS DISTINCT FROM OLD.provider_name
       OR NEW.request_key IS DISTINCT FROM OLD.request_key
       OR NEW.sample_durations_ms IS DISTINCT FROM OLD.sample_durations_ms THEN
        RAISE EXCEPTION 'synthetic clone binding is immutable' USING ERRCODE = '23514';
    END IF;
    IF OLD.status IN ('deleted', 'failed') AND NEW.status <> OLD.status THEN
        RAISE EXCEPTION 'synthetic clone terminal status cannot reopen'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION kof5.guard_synthetic_guardian_clone_update()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER synthetic_guardian_clone_binding_terminal
    BEFORE UPDATE ON kof5.synthetic_guardian_voice_clone
    FOR EACH ROW EXECUTE FUNCTION kof5.guard_synthetic_guardian_clone_update();

CREATE FUNCTION kof5.synthetic_guardian_link_current(
    p_patient_id uuid, p_guardian_user_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT p_patient_id IS NOT DISTINCT FROM
           '00000000-0000-4000-8000-000000000975'::uuid
       AND EXISTS (SELECT 1 FROM auth.users u
                   WHERE u.id = p_guardian_user_id AND u.is_anonymous IS FALSE)
       AND EXISTS (
           SELECT 1 FROM kof5.patient_guardian_link l
           WHERE l.patient_id = p_patient_id
             AND l.guardian_user_id = p_guardian_user_id
             AND l.access_status = 'verified' AND l.revoked_at IS NULL
             AND l.effective_at <= now()
             AND (l.expires_at IS NULL OR l.expires_at > now())
       );
$$;
CREATE FUNCTION kof5.synthetic_guardian_clone_consent_current(
    p_patient_id uuid, p_guardian_user_id uuid, p_consent_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT kof5.synthetic_guardian_link_current(p_patient_id, p_guardian_user_id)
       AND EXISTS (
           SELECT 1 FROM kof5.consent_record c
           WHERE c.consent_id = p_consent_id AND c.patient_id = p_patient_id
             AND c.scope = 'guardian_voice_clone'
             AND c.guardian_ref = p_guardian_user_id::text
             AND c.signer_role = 'guardian'
             AND c.signer_ref = p_guardian_user_id::text
             AND c.status = 'active'
             AND c.assent_status IN ('assented', 'not_required')
             AND c.effective_at <= now() AND c.withdrawn_at IS NULL
             AND (c.expires_at IS NULL OR c.expires_at > now())
       );
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_guardian_link_current(uuid, uuid),
    kof5.synthetic_guardian_clone_consent_current(uuid, uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;

-- The guardian can see only their own metadata, including a deletion tombstone.
-- A withdrawn clone consent blocks use, but does not hide cleanup state.
CREATE FUNCTION kof5.synthetic_guardian_voice_status(p_patient_id uuid)
RETURNS TABLE (
    authorized boolean, ready boolean, consent_id uuid,
    clone_id uuid, status text, provider text,
    provider_name text, created_at timestamptz, remote_absence_verified_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_guardian uuid := auth.uid();
    v_clone kof5.synthetic_guardian_voice_clone%ROWTYPE;
    v_consent_id uuid;
    v_open boolean;
BEGIN
    IF v_guardian IS NULL
       OR COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, true)
       OR NOT kof5.synthetic_guardian_link_current(p_patient_id, v_guardian) THEN
        RETURN QUERY SELECT false, false, NULL::uuid, NULL::uuid,
                            NULL::text, NULL::text, NULL::text,
                            NULL::timestamptz, NULL::timestamptz;
        RETURN;
    END IF;
    SELECT c.consent_id INTO v_consent_id FROM kof5.consent_record c
    WHERE c.patient_id = p_patient_id AND c.scope = 'guardian_voice_clone'
      AND c.guardian_ref = v_guardian::text AND c.signer_role = 'guardian'
      AND c.signer_ref = v_guardian::text
      AND c.status = 'active' AND c.assent_status IN ('assented', 'not_required')
      AND c.effective_at <= now() AND c.withdrawn_at IS NULL
      AND (c.expires_at IS NULL OR c.expires_at > now())
    ORDER BY c.effective_at DESC, c.consent_id LIMIT 1;
    SELECT EXISTS (
        SELECT 1 FROM kof5.synthetic_guardian_voice_clone c
        WHERE c.patient_id = p_patient_id AND c.guardian_user_id = v_guardian
          AND c.status NOT IN ('deleted', 'failed')
    ) INTO v_open;
    SELECT c.* INTO v_clone FROM kof5.synthetic_guardian_voice_clone c
    WHERE c.patient_id = p_patient_id AND c.guardian_user_id = v_guardian
    ORDER BY c.created_at DESC, c.clone_id LIMIT 1;
    RETURN QUERY SELECT true, v_consent_id IS NOT NULL AND NOT v_open,
                        v_consent_id, v_clone.clone_id,
                        COALESCE(v_clone.status, 'none'), v_clone.provider,
                        v_clone.provider_name, v_clone.created_at,
                        v_clone.remote_absence_verified_at;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_guardian_voice_status(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_guardian_voice_status(uuid) TO authenticated;
CREATE FUNCTION api.synthetic_guardian_voice_status(p_patient_id uuid)
RETURNS TABLE (
    authorized boolean, ready boolean, consent_id uuid,
    clone_id uuid, status text, provider text,
    provider_name text, created_at timestamptz, remote_absence_verified_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_status(p_patient_id);
$$;
REVOKE ALL ON FUNCTION api.synthetic_guardian_voice_status(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_guardian_voice_status(uuid) TO authenticated;

-- Only a server-held service_role may receive the hosted voice ID. Every
-- request checks the current verified link and distinct clone consent.
CREATE FUNCTION kof5.synthetic_guardian_voice_tts_ready(
    p_patient_id uuid, p_guardian_user_id uuid
) RETURNS TABLE (authorized boolean, clone_id uuid, provider text, voice_id text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_clone kof5.synthetic_guardian_voice_clone%ROWTYPE;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role'
       OR p_patient_id IS DISTINCT FROM
          '00000000-0000-4000-8000-000000000975'::uuid THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT c.* INTO v_clone FROM kof5.synthetic_guardian_voice_clone c
    WHERE c.patient_id = p_patient_id
      AND c.guardian_user_id = p_guardian_user_id
      AND c.status = 'created' AND c.voice_id IS NOT NULL
      AND kof5.synthetic_guardian_clone_consent_current(
          c.patient_id, c.guardian_user_id, c.consent_id
      )
    ORDER BY c.created_at DESC, c.clone_id LIMIT 1;
    IF v_clone.clone_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text;
    ELSE
        RETURN QUERY SELECT true, v_clone.clone_id, v_clone.provider,
                            v_clone.voice_id;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_guardian_voice_tts_ready(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA kof5, api TO service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_guardian_voice_tts_ready(uuid, uuid)
    TO service_role;
CREATE FUNCTION api.synthetic_guardian_voice_tts_ready(
    p_patient_id uuid, p_guardian_user_id uuid
) RETURNS TABLE (authorized boolean, clone_id uuid, provider text, voice_id text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_tts_ready(
        p_patient_id, p_guardian_user_id
    );
$$;
REVOKE ALL ON FUNCTION api.synthetic_guardian_voice_tts_ready(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_guardian_voice_tts_ready(uuid, uuid)
    TO service_role;

-- The backend calls this only after validating three in-memory 20-30s WAVs
-- and the guardian's own Auth identity. It must save pending before provider POST.
CREATE FUNCTION kof5.synthetic_guardian_voice_begin(
    p_patient_id uuid, p_guardian_user_id uuid, p_consent_id uuid,
    p_provider text, p_request_key uuid, p_sample_durations_ms integer[]
) RETURNS TABLE (
    authorized boolean, clone_id uuid, status text,
    provider_name text, newly_created boolean
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_existing kof5.synthetic_guardian_voice_clone%ROWTYPE;
    v_clone_id uuid;
    v_name text;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role'
       OR p_patient_id IS DISTINCT FROM
          '00000000-0000-4000-8000-000000000975'::uuid
       OR p_guardian_user_id IS NULL OR p_consent_id IS NULL
       OR p_provider IS NULL OR p_provider !~ '^[a-z][a-z0-9_-]{0,39}$'
       OR p_request_key IS NULL OR p_sample_durations_ms IS NULL
       OR cardinality(p_sample_durations_ms) <> 3
       OR array_lower(p_sample_durations_ms, 1) <> 1
       OR array_position(p_sample_durations_ms, NULL) IS NOT NULL
       OR p_sample_durations_ms[1] NOT BETWEEN 20000 AND 30000
       OR p_sample_durations_ms[2] NOT BETWEEN 20000 AND 30000
       OR p_sample_durations_ms[3] NOT BETWEEN 20000 AND 30000 THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, false;
        RETURN;
    END IF;
    PERFORM 1 FROM kof5.patient_guardian_link l
    JOIN kof5.consent_record c
      ON c.patient_id = l.patient_id AND c.guardian_ref = l.guardian_user_id::text
    WHERE l.patient_id = p_patient_id
      AND l.guardian_user_id = p_guardian_user_id
      AND l.access_status = 'verified' AND l.revoked_at IS NULL
      AND l.effective_at <= now()
      AND (l.expires_at IS NULL OR l.expires_at > now())
      AND c.consent_id = p_consent_id AND c.scope = 'guardian_voice_clone'
      AND c.signer_role = 'guardian' AND c.signer_ref = p_guardian_user_id::text
      AND c.status = 'active' AND c.assent_status IN ('assented', 'not_required')
      AND c.effective_at <= now() AND c.withdrawn_at IS NULL
      AND (c.expires_at IS NULL OR c.expires_at > now())
      AND EXISTS (SELECT 1 FROM auth.users u
                  WHERE u.id = p_guardian_user_id AND u.is_anonymous IS FALSE)
    FOR SHARE OF l, c;
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, false;
        RETURN;
    END IF;
    SELECT v.* INTO v_existing FROM kof5.synthetic_guardian_voice_clone v
    WHERE v.request_key = p_request_key FOR UPDATE;
    IF FOUND THEN
        IF v_existing.patient_id = p_patient_id
           AND v_existing.guardian_user_id = p_guardian_user_id
           AND v_existing.consent_id = p_consent_id
           AND v_existing.provider = p_provider
           AND v_existing.sample_durations_ms = p_sample_durations_ms THEN
            RETURN QUERY SELECT true, v_existing.clone_id,
                                v_existing.status, v_existing.provider_name, false;
        ELSE
            RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, false;
        END IF;
        RETURN;
    END IF;
    v_name := 'KoF5 internal self-voice test '
              || replace(p_request_key::text, '-', '');
    INSERT INTO kof5.synthetic_guardian_voice_clone (
        patient_id, guardian_user_id, consent_id, provider,
        provider_name, request_key, sample_durations_ms
    ) VALUES (
        p_patient_id, p_guardian_user_id, p_consent_id, p_provider,
        v_name, p_request_key, p_sample_durations_ms
    ) ON CONFLICT DO NOTHING RETURNING kof5.synthetic_guardian_voice_clone.clone_id
      INTO v_clone_id;
    IF v_clone_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, false;
    ELSE
        RETURN QUERY SELECT true, v_clone_id, 'pending'::text, v_name, true;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_guardian_voice_begin(
    uuid, uuid, uuid, text, uuid, integer[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_guardian_voice_begin(
    uuid, uuid, uuid, text, uuid, integer[]
) TO service_role;
CREATE FUNCTION api.synthetic_guardian_voice_begin(
    p_patient_id uuid, p_guardian_user_id uuid, p_consent_id uuid,
    p_provider text, p_request_key uuid, p_sample_durations_ms integer[]
) RETURNS TABLE (
    authorized boolean, clone_id uuid, status text,
    provider_name text, newly_created boolean
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_begin(
        p_patient_id, p_guardian_user_id, p_consent_id,
        p_provider, p_request_key, p_sample_durations_ms
    );
$$;
REVOKE ALL ON FUNCTION api.synthetic_guardian_voice_begin(
    uuid, uuid, uuid, text, uuid, integer[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.synthetic_guardian_voice_begin(
    uuid, uuid, uuid, text, uuid, integer[]
) TO service_role;

-- The private transition gate accepts only server-held service_role callers.
-- Unknown provider create result remains pending until name/ID reconciliation.
-- A DELETE HTTP response is not a transition: only a separate remote absence
-- check can supply the explicit method and observation time below.
CREATE FUNCTION kof5.synthetic_guardian_voice_transition(
    p_clone_id uuid, p_action text, p_voice_id text,
    p_verification_confirmed boolean, p_method text, p_checked_at timestamptz
) RETURNS TABLE (
    authorized boolean, clone_id uuid, status text, provider_name text, voice_id text
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_clone kof5.synthetic_guardian_voice_clone%ROWTYPE;
    v_current boolean;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' OR p_clone_id IS NULL
       OR p_action IS NULL OR p_action NOT IN (
           'provider_result', 'request_deletion', 'confirm_remote_absence',
           'confirm_failure'
       ) THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT c.* INTO v_clone FROM kof5.synthetic_guardian_voice_clone c
    WHERE c.clone_id = p_clone_id
      AND c.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    IF p_action = 'provider_result' THEN
        IF p_voice_id IS NULL OR p_voice_id !~ '^[A-Za-z0-9_-]{1,100}$'
           OR v_clone.status IN ('deleted', 'failed')
           OR (v_clone.voice_id IS NOT NULL AND v_clone.voice_id <> p_voice_id) THEN
            RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
            RETURN;
        END IF;
        v_current := kof5.synthetic_guardian_clone_consent_current(
            v_clone.patient_id, v_clone.guardian_user_id, v_clone.consent_id
        );
        IF v_clone.status = 'created' AND v_current THEN
            RETURN QUERY SELECT true, v_clone.clone_id, v_clone.status,
                                v_clone.provider_name, v_clone.voice_id;
            RETURN;
        END IF;
        UPDATE kof5.synthetic_guardian_voice_clone c
        SET voice_id = p_voice_id,
            provider_created_at = COALESCE(c.provider_created_at, now()),
            status = CASE WHEN c.status = 'deletion_pending' OR NOT v_current
                         THEN 'deletion_pending'
                         WHEN p_verification_confirmed IS TRUE THEN 'created'
                         ELSE 'verification_pending' END,
            verification_confirmed_at = CASE
                WHEN c.status <> 'deletion_pending' AND v_current
                 AND p_verification_confirmed IS TRUE
                THEN COALESCE(c.verification_confirmed_at, now())
                ELSE c.verification_confirmed_at END,
            deletion_requested_at = CASE
                WHEN c.status = 'deletion_pending' OR NOT v_current
                THEN COALESCE(c.deletion_requested_at, now())
                ELSE c.deletion_requested_at END,
            last_transition_at = now()
        WHERE c.clone_id = p_clone_id
        RETURNING c.* INTO v_clone;
    ELSIF p_action = 'request_deletion' THEN
        IF v_clone.status = 'failed' THEN
            RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
            RETURN;
        END IF;
        IF v_clone.status NOT IN ('deletion_pending', 'deleted') THEN
            UPDATE kof5.synthetic_guardian_voice_clone c
            SET status = 'deletion_pending',
                deletion_requested_at = COALESCE(c.deletion_requested_at, now()),
                last_transition_at = now()
            WHERE c.clone_id = p_clone_id RETURNING c.* INTO v_clone;
        END IF;
    ELSIF p_action = 'confirm_remote_absence' THEN
        IF v_clone.status = 'deleted' THEN
            RETURN QUERY SELECT true, v_clone.clone_id, v_clone.status,
                                v_clone.provider_name, v_clone.voice_id;
            RETURN;
        END IF;
        IF v_clone.status <> 'deletion_pending' OR p_checked_at IS NULL
           OR p_checked_at < v_clone.deletion_requested_at
           OR p_checked_at > now() + interval '5 seconds'
           OR (v_clone.voice_id IS NOT NULL AND p_method <> 'voice_id_not_found')
           OR (v_clone.voice_id IS NULL AND p_method <> 'provider_name_not_found')
           OR p_method IS NULL THEN
            RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
            RETURN;
        END IF;
        UPDATE kof5.synthetic_guardian_voice_clone c
        SET status = 'deleted', remote_absence_verified_at = now(),
            last_transition_at = now()
        WHERE c.clone_id = p_clone_id RETURNING c.* INTO v_clone;
    ELSE
        -- Only an explicit provider rejection before any voice ID is known is
        -- confirmed failure. Network uncertainty is not evidence of failure.
        IF v_clone.status = 'failed' THEN
            RETURN QUERY SELECT true, v_clone.clone_id, v_clone.status,
                                v_clone.provider_name, v_clone.voice_id;
            RETURN;
        END IF;
        IF v_clone.status <> 'pending' OR v_clone.voice_id IS NOT NULL THEN
            RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, NULL::text;
            RETURN;
        END IF;
        UPDATE kof5.synthetic_guardian_voice_clone c
        SET status = 'failed', failure_code = 'provider_rejected',
            last_transition_at = now()
        WHERE c.clone_id = p_clone_id RETURNING c.* INTO v_clone;
    END IF;
    RETURN QUERY SELECT true, v_clone.clone_id, v_clone.status,
                        v_clone.provider_name, v_clone.voice_id;
END;
$$;
REVOKE ALL ON FUNCTION kof5.synthetic_guardian_voice_transition(
    uuid, text, text, boolean, text, timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION kof5.synthetic_guardian_voice_transition(
    uuid, text, text, boolean, text, timestamptz
) TO service_role;

CREATE FUNCTION api.synthetic_guardian_voice_provider_result(
    p_clone_id uuid, p_voice_id text, p_verification_confirmed boolean
) RETURNS TABLE (
    authorized boolean, clone_id uuid, status text, provider_name text, voice_id text
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_transition(
        p_clone_id, 'provider_result', p_voice_id,
        p_verification_confirmed, NULL::text, NULL::timestamptz
    );
$$;
CREATE FUNCTION api.synthetic_guardian_voice_request_deletion(p_clone_id uuid)
RETURNS TABLE (
    authorized boolean, clone_id uuid, status text, provider_name text, voice_id text
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_transition(
        p_clone_id, 'request_deletion', NULL::text,
        NULL::boolean, NULL::text, NULL::timestamptz
    );
$$;
CREATE FUNCTION api.synthetic_guardian_voice_confirm_remote_absence(
    p_clone_id uuid, p_method text, p_checked_at timestamptz
) RETURNS TABLE (
    authorized boolean, clone_id uuid, status text, provider_name text, voice_id text
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_transition(
        p_clone_id, 'confirm_remote_absence', NULL::text,
        NULL::boolean, p_method, p_checked_at
    );
$$;
CREATE FUNCTION api.synthetic_guardian_voice_confirm_failure(p_clone_id uuid)
RETURNS TABLE (
    authorized boolean, clone_id uuid, status text, provider_name text, voice_id text
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT * FROM kof5.synthetic_guardian_voice_transition(
        p_clone_id, 'confirm_failure', NULL::text,
        NULL::boolean, NULL::text, NULL::timestamptz
    );
$$;
REVOKE ALL ON FUNCTION
    api.synthetic_guardian_voice_provider_result(uuid, text, boolean),
    api.synthetic_guardian_voice_request_deletion(uuid),
    api.synthetic_guardian_voice_confirm_remote_absence(uuid, text, timestamptz),
    api.synthetic_guardian_voice_confirm_failure(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
    api.synthetic_guardian_voice_provider_result(uuid, text, boolean),
    api.synthetic_guardian_voice_request_deletion(uuid),
    api.synthetic_guardian_voice_confirm_remote_absence(uuid, text, timestamptz),
    api.synthetic_guardian_voice_confirm_failure(uuid)
    TO service_role;
