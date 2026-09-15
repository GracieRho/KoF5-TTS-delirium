-- Synthetic fixture only. The client may read short, approved orientation or
-- scheduling facts for its own current encounter. Category and lexical screens
-- are limited guards; a real institution needs a trusted writer/clinical review.
ALTER POLICY hospital_context_verified_staff_read
    ON kof5.hospital_context_fact USING (
        EXISTS (
            SELECT 1 FROM kof5.hospital_patient p
            WHERE p.patient_id = hospital_context_fact.patient_id
        ) OR (
            patient_id = '00000000-0000-4000-8000-000000000975'::uuid
            AND COALESCE(((SELECT auth.jwt()) ->> 'is_anonymous')::boolean, false)
            AND kof5.anonymous_auth_user((SELECT auth.uid()))
            AND status = 'approved' AND revoked_at IS NULL
            AND verified_at <= now()
            AND (valid_until IS NULL OR valid_until > now())
            AND category IN ('hospital', 'ward', 'room', 'test_schedule', 'visit_schedule')
            AND char_length(btrim(content)) BETWEEN 1 AND 200
            AND content !~ '(진단|치료|처방|약|수술|통증|증상|괜찮|위험|복용|투약)'
            AND EXISTS (
                SELECT 1 FROM kof5.patient_device_assignment d
                WHERE d.device_user_id = (SELECT auth.uid())
                  AND d.patient_id = hospital_context_fact.patient_id
                  AND (hospital_context_fact.encounter_id = d.encounter_id
                       OR (hospital_context_fact.encounter_id IS NULL
                           AND hospital_context_fact.category = 'hospital'))
            )
        )
    );

-- The STABLE invoker RPC resolves authorization and facts in one statement
-- snapshot. An authorized empty result differs from a revoked device/consent.
CREATE FUNCTION api.patient_hospital_turn_context(p_patient_id uuid, p_term text)
RETURNS TABLE (authorized boolean, facts jsonb)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
    WITH eligible AS (
        SELECT d.encounter_id
        FROM api.patient_device_context d
        WHERE d.patient_id = p_patient_id
          AND p_patient_id = '00000000-0000-4000-8000-000000000975'::uuid
    ), matches AS (
        SELECT f.category, f.content, f.verified_at, f.valid_until,
               f.encounter_id, f.fact_id
        FROM eligible d
        JOIN kof5.hospital_context_fact f ON f.patient_id = p_patient_id
        WHERE (f.encounter_id = d.encounter_id
               OR (f.encounter_id IS NULL AND f.category = 'hospital'))
          AND f.status = 'approved' AND f.revoked_at IS NULL
          AND f.verified_at <= now()
          AND (f.valid_until IS NULL OR f.valid_until > now())
          AND f.category IN ('hospital', 'ward', 'room', 'test_schedule', 'visit_schedule')
          AND char_length(btrim(f.content)) BETWEEN 1 AND 200
          AND f.content !~ '(진단|치료|처방|약|수술|통증|증상|괜찮|위험|복용|투약)'
          AND char_length(btrim(p_term)) BETWEEN 2 AND 200
          AND p_term !~ '(결과|진단|치료|처방|약|수술|통증|증상|괜찮|위험)'
          AND (
              (f.category = 'hospital' AND p_term ~
                  '((어느|무슨|어디).{0,20}병원|병원.{0,20}(이름|명칭|어디|어느|무슨))')
              OR (f.category IN ('ward', 'room')
                  AND p_term ~ '(병동|병실|호실|방)'
                  AND p_term ~ '(어디|몇|어느|위치)')
              OR (f.category IN ('test_schedule', 'visit_schedule')
                  AND p_term ~ CASE WHEN f.category = 'test_schedule'
                      THEN '(검사|촬영|일정)' ELSE '(면회|방문|일정)' END
                  AND EXISTS (
                      SELECT 1
                      FROM regexp_split_to_table(p_term, '[^가-힣A-Za-z0-9]+') AS word(raw)
                      CROSS JOIN LATERAL (
                          SELECT regexp_replace(word.raw,
                              '(에서|에게|은|는|이|가|을|를|에)$', '') AS token
                      ) AS term
                      WHERE char_length(term.token) >= 2
                        AND term.token NOT IN (
                            '검사', '촬영', '일정', '면회', '방문',
                            '언제', '어디', '무엇', '지금', '오늘', '내일', '몇시', '시간'
                        )
                        AND position(lower(term.token) IN lower(
                            regexp_replace(f.content, '[[:space:]]+', '', 'g'))) > 0
                  ))
          )
        ORDER BY f.verified_at DESC, f.fact_id
        LIMIT 3
    )
    SELECT EXISTS (SELECT 1 FROM eligible) AS authorized,
           CASE WHEN (SELECT count(*) FROM matches) = 1 THEN
               (SELECT jsonb_build_array(jsonb_build_object(
                   'category', m.category, 'content', m.content,
                   'verified_at', m.verified_at, 'valid_until', m.valid_until,
                   'encounter_id', m.encounter_id
               )) FROM matches m)
           ELSE '[]'::jsonb END AS facts;
$$;
REVOKE ALL ON FUNCTION api.patient_hospital_turn_context(uuid, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.patient_hospital_turn_context(uuid, text)
    TO authenticated;
