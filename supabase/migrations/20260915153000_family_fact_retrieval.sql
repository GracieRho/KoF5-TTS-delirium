-- Small, literal search of guardian-authored family facts. This is a lexical
-- baseline for synthetic testing, not semantic RAG or a patient-use endpoint.
-- Existing family_fact RLS and verified guardian linkage remain the authority.
CREATE FUNCTION api.guardian_memory_search(p_patient_id uuid, p_term text)
RETURNS TABLE (fact_id uuid, category text, content text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT f.fact_id, f.category, f.content, f.created_at
    FROM kof5.family_fact AS f
    WHERE f.patient_id = p_patient_id
      AND f.author_guardian_user_id = (SELECT auth.uid())
      AND f.active
      AND f.sensitivity = 'ordinary'
      AND f.category <> 'avoid_topic'
      AND f.valid_from <= now()
      AND (f.valid_until IS NULL OR f.valid_until > now())
      AND char_length(btrim(p_term)) BETWEEN 2 AND 80
      AND position(lower(btrim(p_term)) IN lower(f.content)) > 0
    ORDER BY f.created_at DESC, f.fact_id
    LIMIT 3;
$$;

REVOKE ALL ON FUNCTION api.guardian_memory_search(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.guardian_memory_search(uuid, text) TO authenticated;
-- ponytail: 20-30 onboarding facts need no vector index; add embeddings only after
-- Korean retrieval misses are measured on approved synthetic/consented material.
