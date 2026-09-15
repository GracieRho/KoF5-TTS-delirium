-- Evaluation-only family namespace, pinned synthetic patient. The provisional
-- OpenAI text-embedding-3-small default has 1536 dimensions; this does not
-- establish Korean clinical retrieval quality or authorize patient material.
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

CREATE TABLE kof5.family_fact_embedding (
    fact_id uuid PRIMARY KEY REFERENCES kof5.family_fact (fact_id) ON DELETE CASCADE,
    patient_id uuid NOT NULL CHECK (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ),
    model text NOT NULL CHECK (model = 'text-embedding-3-small'),
    content_md5 text NOT NULL CHECK (content_md5 ~ '^[0-9a-f]{32}$'),
    embedding extensions.vector(1536) NOT NULL CHECK (extensions.vector_norm(embedding) > 0),
    embedded_at timestamptz NOT NULL DEFAULT now()
);
-- Fact-id lookup precedes exact cosine ranking over 20-30 guardian facts;
-- an approximate cross-patient HNSW pool could miss filtered safe facts.
CREATE INDEX family_fact_embedding_patient_idx
    ON kof5.family_fact_embedding (patient_id, fact_id);
ALTER TABLE kof5.family_fact_embedding ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_fact_embedding FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.family_fact_embedding
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON kof5.family_fact_embedding TO authenticated;

CREATE POLICY paired_device_current_family_embedding_read
    ON kof5.family_fact_embedding FOR SELECT TO authenticated
    USING (
        patient_id = '00000000-0000-4000-8000-000000000975'::uuid
        AND model = 'text-embedding-3-small'
        AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
        AND kof5.anonymous_auth_user((SELECT auth.uid()))
        AND EXISTS (
            SELECT 1 FROM kof5.family_fact f
            WHERE f.fact_id = family_fact_embedding.fact_id
              AND f.patient_id = family_fact_embedding.patient_id
              AND NOT kof5.anonymous_auth_user(f.author_guardian_user_id)
              AND kof5.device_guardian_fact_ready(
                  f.patient_id, f.author_guardian_user_id
              )
              AND f.active AND f.sensitivity = 'ordinary'
              AND f.category IN (
                  'family', 'relationship', 'hometown', 'occupation', 'travel',
                  'food', 'hobby', 'friend', 'pet', 'family_event', 'daily_routine',
                  'favorite_story', 'recent_event', 'comfort_topic'
              )
              AND f.valid_from <= now()
              AND (f.valid_until IS NULL OR f.valid_until > now())
              AND md5(f.content) = family_fact_embedding.content_md5
        )
    );

-- SECURITY DEFINER stays in the private schema. The exposed wrapper below is
-- invoker and executable only by a server-held service_role credential.
CREATE FUNCTION kof5.upsert_synthetic_family_fact_embedding(
    p_fact_id uuid, p_embedding extensions.vector(1536),
    p_model text, p_content_md5 text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    current_content text;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role'
       OR p_fact_id IS NULL
       OR p_model IS DISTINCT FROM 'text-embedding-3-small'
       OR p_content_md5 IS NULL
       OR p_content_md5 !~ '^[0-9a-f]{32}$'
       OR p_embedding IS NULL
       OR COALESCE(extensions.vector_norm(p_embedding), 0) <= 0 THEN
        RAISE EXCEPTION 'synthetic family embedding writer denied'
            USING ERRCODE = '42501';
    END IF;

    SELECT f.content INTO current_content
    FROM kof5.family_fact f
    JOIN kof5.patient_guardian_link l
      ON l.patient_id = f.patient_id
     AND l.guardian_user_id = f.author_guardian_user_id
    WHERE f.fact_id = p_fact_id
      AND f.patient_id = '00000000-0000-4000-8000-000000000975'::uuid
      AND f.active AND f.sensitivity = 'ordinary'
      AND f.category IN (
          'family', 'relationship', 'hometown', 'occupation', 'travel',
          'food', 'hobby', 'friend', 'pet', 'family_event', 'daily_routine',
          'favorite_story', 'recent_event', 'comfort_topic'
      )
      AND f.valid_from <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND l.access_status = 'verified' AND l.revoked_at IS NULL
      AND l.effective_at <= now()
      AND (l.expires_at IS NULL OR l.expires_at > now())
      AND EXISTS (
          SELECT 1 FROM auth.users u
          WHERE u.id = f.author_guardian_user_id AND u.is_anonymous IS FALSE
      )
    FOR SHARE OF f, l;
    IF current_content IS NULL OR md5(current_content) <> p_content_md5 THEN
        RETURN false;
    END IF;

    INSERT INTO kof5.family_fact_embedding (
        fact_id, patient_id, model, content_md5, embedding
    ) VALUES (
        p_fact_id, '00000000-0000-4000-8000-000000000975'::uuid,
        p_model, p_content_md5, p_embedding
    ) ON CONFLICT (fact_id) DO UPDATE
      SET model = EXCLUDED.model,
          content_md5 = EXCLUDED.content_md5,
          embedding = EXCLUDED.embedding,
          embedded_at = now();
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION kof5.upsert_synthetic_family_fact_embedding(
    uuid, extensions.vector(1536), text, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA kof5 TO service_role;
GRANT EXECUTE ON FUNCTION kof5.upsert_synthetic_family_fact_embedding(
    uuid, extensions.vector(1536), text, text
) TO service_role;

CREATE FUNCTION api.upsert_synthetic_family_fact_embedding(
    p_fact_id uuid, p_embedding extensions.vector(1536),
    p_model text, p_content_md5 text
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT kof5.upsert_synthetic_family_fact_embedding(
        p_fact_id, p_embedding, p_model, p_content_md5
    );
$$;
REVOKE ALL ON FUNCTION api.upsert_synthetic_family_fact_embedding(
    uuid, extensions.vector(1536), text, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA api TO service_role;
GRANT EXECUTE ON FUNCTION api.upsert_synthetic_family_fact_embedding(
    uuid, extensions.vector(1536), text, text
) TO service_role;

-- One STABLE invoker statement snapshot distinguishes no matching semantic
-- facts from device/consent revocation. Neither vector nor score is returned.
-- 0.75 cosine similarity is an uncalibrated synthetic-only evaluation gate.
CREATE FUNCTION api.patient_family_semantic_turn_context(
    p_patient_id uuid, p_query_embedding extensions.vector(1536)
) RETURNS TABLE (authorized boolean, facts jsonb)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    WITH eligible AS (
        SELECT d.patient_id
        FROM api.patient_device_context d
        WHERE d.patient_id = p_patient_id
          AND p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ), matches AS (
        SELECT f.fact_id, f.category, f.content,
               e.embedding OPERATOR(extensions.<=>) p_query_embedding AS distance
        FROM eligible d
        JOIN kof5.family_fact f ON f.patient_id = d.patient_id
        JOIN kof5.family_fact_embedding e
          ON e.fact_id = f.fact_id AND e.patient_id = f.patient_id
        WHERE p_query_embedding IS NOT NULL
          AND extensions.vector_norm(p_query_embedding) > 0
          AND e.model = 'text-embedding-3-small'
          AND e.content_md5 = md5(f.content)
          AND NOT kof5.anonymous_auth_user(f.author_guardian_user_id)
          AND kof5.device_guardian_fact_ready(
              f.patient_id, f.author_guardian_user_id
          )
          AND f.active AND f.sensitivity = 'ordinary'
          AND f.category IN (
              'family', 'relationship', 'hometown', 'occupation', 'travel',
              'food', 'hobby', 'friend', 'pet', 'family_event', 'daily_routine',
              'favorite_story', 'recent_event', 'comfort_topic'
          )
          AND f.valid_from <= now()
          AND (f.valid_until IS NULL OR f.valid_until > now())
          AND 1 - (e.embedding OPERATOR(extensions.<=>) p_query_embedding) >= 0.75
        ORDER BY e.embedding OPERATOR(extensions.<=>) p_query_embedding, f.fact_id
        LIMIT 3
    )
    SELECT EXISTS (SELECT 1 FROM eligible) AS authorized,
           COALESCE((SELECT jsonb_agg(jsonb_build_object(
               'category', m.category, 'content', m.content
           ) ORDER BY m.distance, m.fact_id) FROM matches m), '[]'::jsonb)
           AS facts;
$$;
REVOKE ALL ON FUNCTION api.patient_family_semantic_turn_context(
    uuid, extensions.vector(1536)
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.patient_family_semantic_turn_context(
    uuid, extensions.vector(1536)
) TO authenticated;
