-- A single invoker statement resolves eligibility and bounded family context.
-- STABLE SQL functions use the calling query's snapshot, so a withdrawal
-- committed before this RPC starts cannot become an authorized empty result.
-- Pinned synthetic patient only; this is not approval for patient use.
CREATE FUNCTION api.patient_family_turn_context(p_patient_id uuid, p_term text)
RETURNS TABLE (authorized boolean, facts jsonb)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    WITH eligibility AS (
        SELECT COALESCE(
            p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid, false
        ) AND EXISTS (
            SELECT 1 FROM api.patient_device_context d
            WHERE d.patient_id = p_patient_id
        ) AS allowed
    )
    SELECT e.allowed AS authorized,
           CASE WHEN e.allowed THEN (
               SELECT COALESCE(
                   jsonb_agg(jsonb_build_object(
                       'category', f.category, 'content', f.content
                   ) ORDER BY f.ordinality), '[]'::jsonb
               )
               FROM api.patient_family_search(p_patient_id, p_term)
                    WITH ORDINALITY AS f(category, content, ordinality)
           ) ELSE '[]'::jsonb END AS facts
    FROM eligibility e;
$$;
REVOKE ALL ON FUNCTION api.patient_family_turn_context(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.patient_family_turn_context(uuid, text)
    TO authenticated;
