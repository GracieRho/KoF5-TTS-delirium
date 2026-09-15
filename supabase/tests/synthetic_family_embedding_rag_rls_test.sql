BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(37);

-- Orthogonal 1536-dimensional placeholders prove DB gates, not Korean recall.
CREATE TEMP TABLE synthetic_rag_vectors AS
SELECT ('[' || array_to_string(
        ARRAY[1::real] || array_fill(0::real, ARRAY[1535]), ',') || ']')
        ::extensions.vector(1536) AS related,
       ('[' || array_to_string(
        ARRAY[0::real, 1::real] || array_fill(0::real, ARRAY[1534]), ',') || ']')
        ::extensions.vector(1536) AS unrelated;
GRANT SELECT ON synthetic_rag_vectors TO service_role, authenticated;

INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000971', false),
    ('00000000-0000-4000-8000-000000000972', true),
    ('00000000-0000-4000-8000-000000000973', true),
    ('00000000-0000-4000-8000-000000000974', false);
INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000975', 'TEST-RAG', 'TEST-P', '가상 환자', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000977', 'TEST-RAG', 'TEST-Q', '가상 다른 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status, admitted_at
) VALUES
    ('00000000-0000-4000-8000-000000000976', '00000000-0000-4000-8000-000000000975',
     'TEST-CURRENT', 'in_progress', now() - interval '1 day'),
    ('00000000-0000-4000-8000-000000000978', '00000000-0000-4000-8000-000000000977',
     'TEST-OTHER', 'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation (
    hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref,
    approved_at, expires_at
) VALUES ('TEST-RAG', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY',
          now() - interval '1 day', now() + interval '1 day');
INSERT INTO kof5.consent_record (
    consent_id, patient_id, scope, signer_role, signer_ref,
    assent_status, status, effective_at, recorded_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000951', '00000000-0000-4000-8000-000000000975',
     'patient_participation', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000952', '00000000-0000-4000-8000-000000000975',
     'ambient_processing', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000953', '00000000-0000-4000-8000-000000000975',
     'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented', 'active',
     now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile (
    patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
    embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
    enrolled_by_staff_ref, enrolled_at
) VALUES ('00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000976',
          '00000000-0000-4000-8000-000000000953', 'active', 30000,
          'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted',
          'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_guardian_link (
    patient_id, guardian_user_id, relationship, access_status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES
    ('00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', '가상 가족', 'verified',
     now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000972', '가상 잘못 발급된 연결', 'verified',
     now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000977',
     '00000000-0000-4000-8000-000000000974', '가상 다른 환자 가족', 'verified',
     now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.patient_device_assignment (
    device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at
) VALUES ('00000000-0000-4000-8000-000000000972',
          '00000000-0000-4000-8000-000000000975',
          '00000000-0000-4000-8000-000000000976',
          '00000000-0000-4000-8000-000000000971', now() + interval '2 hours');
INSERT INTO kof5.family_fact (
    fact_id, patient_id, author_guardian_user_id, category, content,
    sensitivity, active, valid_from, valid_until
) VALUES
    ('00000000-0000-4000-8000-000000009101', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'travel', '가상 제주도 가족 여행 기억',
     'ordinary', true, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009102', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'avoid_topic', '가상 피할 제주도 사고',
     'ordinary', true, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009103', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'friend', '가상 민감 제주도 사실',
     'sensitive', true, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009104', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'travel', '가상 만료 제주도 여행',
     'ordinary', true, now() - interval '2 days', now() - interval '1 day'),
    ('00000000-0000-4000-8000-000000009105', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'travel', '가상 비활성 제주도 여행',
     'ordinary', false, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009106', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000972', 'family', '가상 장치 제주도 사실',
     'ordinary', true, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009107', '00000000-0000-4000-8000-000000000977',
     '00000000-0000-4000-8000-000000000974', 'travel', '가상 다른 환자 제주도 사실',
     'ordinary', true, now() - interval '1 day', NULL),
    ('00000000-0000-4000-8000-000000009108', '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000974', 'hospital', '가상 병원 사실인 척한 가족 입력',
     'ordinary', true, now() - interval '1 day', NULL);

SELECT ok(NOT has_function_privilege('anon',
    'api.patient_family_semantic_turn_context(uuid,extensions.vector)', 'EXECUTE'),
    'signed-out role cannot call semantic turn');
SELECT ok(NOT has_function_privilege('service_role',
    'api.patient_family_semantic_turn_context(uuid,extensions.vector)', 'EXECUTE'),
    'service role cannot bypass semantic device turn');
SELECT ok(has_function_privilege('authenticated',
    'api.patient_family_semantic_turn_context(uuid,extensions.vector)', 'EXECUTE'),
    'authenticated device may call invoker semantic turn');
SELECT ok(NOT has_function_privilege('authenticated',
    'api.upsert_synthetic_family_fact_embedding(uuid,extensions.vector,text,text)', 'EXECUTE'),
    'guardian and anonymous device cannot invoke embedding writer');
SELECT ok(has_function_privilege('service_role',
    'api.upsert_synthetic_family_fact_embedding(uuid,extensions.vector,text,text)', 'EXECUTE'),
    'server-only service role can invoke embedding writer');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.family_fact_embedding', 'INSERT'),
    'device and guardian cannot directly insert embedding rows');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.family_fact_embedding', 'UPDATE'),
    'device and guardian cannot directly replace embeddings');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.patient_family_semantic_turn_context(uuid,extensions.vector)'::regprocedure),
    'semantic turn is security invoker');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.upsert_synthetic_family_fact_embedding(uuid,extensions.vector,text,text)'::regprocedure),
    'exposed writer wrapper is security invoker');
SELECT ok((SELECT relforcerowsecurity FROM pg_class
    WHERE oid = 'kof5.family_fact_embedding'::regclass),
    'private embedding rows force RLS');

GRANT service_role, authenticated TO postgres WITH SET TRUE;
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT lives_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 제주도 가족 여행 기억'))$sql$,
    'service-only writer accepts ordinary current permanent-guardian fact');
SELECT throws_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'wrong-model', md5('가상 제주도 가족 여행 기억'))$sql$, '42501',
    'synthetic family embedding writer denied', 'writer rejects wrong embedding model');
SELECT throws_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    NULL, (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 제주도 가족 여행 기억'))$sql$, '42501',
    'synthetic family embedding writer denied', 'writer rejects null fact ID');
SELECT throws_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    NULL, md5('가상 제주도 가족 여행 기억'))$sql$, '42501',
    'synthetic family embedding writer denied', 'writer rejects null model');
SELECT throws_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', NULL)$sql$, '42501',
    'synthetic family embedding writer denied', 'writer rejects null source hash');
SELECT throws_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', NULL,
    'text-embedding-3-small', md5('가상 제주도 가족 여행 기억'))$sql$, '42501',
    'synthetic family embedding writer denied', 'writer rejects null vector');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('old content')),
    'writer returns false for stale content hash');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009102', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 피할 제주도 사고')),
    'writer returns false for avoid_topic');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009103', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 민감 제주도 사실')),
    'writer returns false for sensitive fact');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009104', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 만료 제주도 여행')),
    'writer returns false for expired fact');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009105', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 비활성 제주도 여행')),
    'writer returns false for inactive fact');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009106', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 장치 제주도 사실')),
    'misissued anonymous guardian cannot author indexed facts');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009107', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 다른 환자 제주도 사실')),
    'writer returns false for other patient UUID');
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009108', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 병원 사실인 척한 가족 입력')),
    'guardian hospital-category spoof cannot enter semantic family index');
RESET ROLE;

-- Simulate a privileged preexisting unsafe index; read-time filters still deny.
INSERT INTO kof5.family_fact_embedding
    (fact_id, patient_id, model, content_md5, embedding)
SELECT f.fact_id, f.patient_id, 'text-embedding-3-small', md5(f.content), v.related
FROM kof5.family_fact f CROSS JOIN synthetic_rag_vectors v
WHERE f.fact_id IN (
    '00000000-0000-4000-8000-000000009102',
    '00000000-0000-4000-8000-000000009103',
    '00000000-0000-4000-8000-000000009104',
    '00000000-0000-4000-8000-000000009105',
    '00000000-0000-4000-8000-000000009106',
    '00000000-0000-4000-8000-000000009108'
);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT is((SELECT count(*)::integer FROM kof5.family_fact_embedding), 0,
    'guardian cannot enumerate raw patient embeddings');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'guardian cannot use device semantic turn');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000973","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'unpaired anonymous device receives explicit false');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM kof5.family_fact_embedding), 1,
    'paired device RLS hides preexisting avoid/sensitive/expired/inactive/device-authored rows');
SELECT is((SELECT count(*)::integer FROM kof5.family_fact_embedding
           WHERE fact_id = '00000000-0000-4000-8000-000000009108'), 0,
    'forged hospital-category fact cannot cross semantic family namespace');
SELECT ok((SELECT authorized IS TRUE AND facts = jsonb_build_array(
    jsonb_build_object('category', 'travel', 'content', '가상 제주도 가족 여행 기억'))
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'same-vector synthetic turn returns only permanent ordinary guardian fact');
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT unrelated FROM synthetic_rag_vectors))),
    'orthogonal unrelated query is authorized but returns no memory');
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000977',
        (SELECT related FROM synthetic_rag_vectors))),
    'other patient UUID cannot cross tenant boundary');
RESET ROLE;

UPDATE kof5.family_fact SET content = '가상 변경된 제주도 가족 여행 기억'
WHERE fact_id = '00000000-0000-4000-8000-000000009101';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'guardian edit immediately invalidates stale embedding via content hash');
RESET ROLE;
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok(NOT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 제주도 가족 여행 기억')),
    'late old-content writer cannot revive stale vector');
SELECT lives_ok($sql$SELECT api.upsert_synthetic_family_fact_embedding(
    '00000000-0000-4000-8000-000000009101', (SELECT related FROM synthetic_rag_vectors),
    'text-embedding-3-small', md5('가상 변경된 제주도 가족 여행 기억'))$sql$,
    'current-content writer refreshes embedding after guardian edit');
RESET ROLE;

UPDATE kof5.patient_guardian_link SET access_status = 'revoked', revoked_at = now()
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974'
  AND patient_id = '00000000-0000-4000-8000-000000000975';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'guardian link revocation removes indexed fact without revoking device turn');
RESET ROLE;
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000952';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND facts = '[]'::jsonb
    FROM api.patient_family_semantic_turn_context(
        '00000000-0000-4000-8000-000000000975',
        (SELECT related FROM synthetic_rag_vectors))),
    'ambient consent withdrawal cannot look like authorized no-match');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
