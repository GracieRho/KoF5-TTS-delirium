BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(13);

-- Synthetic rows are rolled back; no patient identifiers or clinical audio.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-000000000501'),
    ('00000000-0000-4000-8000-000000000502'),
    ('00000000-0000-4000-8000-000000000503');
INSERT INTO kof5.hospital_patient (
    patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref
) VALUES
    ('00000000-0000-4000-8000-000000000601', 'TEST-M1', 'TEST-MP1', '가상 A', 'TEST-STAFF'),
    ('00000000-0000-4000-8000-000000000602', 'TEST-M1', 'TEST-MP2', '가상 B', 'TEST-STAFF');
INSERT INTO kof5.patient_guardian_link (
    patient_id, guardian_user_id, relationship, access_status,
    effective_at, verified_by_staff_ref, verified_at
) VALUES
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     '가상 딸', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000502',
     '가상 아들', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
    ('00000000-0000-4000-8000-000000000602', '00000000-0000-4000-8000-000000000503',
     '가상 기타', 'pending', NULL, NULL, NULL);
INSERT INTO kof5.family_fact (
    patient_id, author_guardian_user_id, category, content,
    sensitivity, valid_from, valid_until, active
) VALUES
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'travel', '수민과 제주도 여행', 'ordinary', now() - interval '1 day', NULL, true),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'avoid_topic', '제주도 사고 이야기', 'ordinary', now() - interval '1 day', NULL, true),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'friend', '제주도 민감한 이름', 'sensitive', now() - interval '1 day', NULL, true),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'food', '제주도 예전 음식', 'ordinary', now() - interval '3 days', now() - interval '1 day', true),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'hobby', '제주도 미래 취미', 'ordinary', now() + interval '1 day', NULL, true),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000501',
     'pet', '제주도 비활성 기억', 'ordinary', now() - interval '1 day', NULL, false),
    ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000502',
     'travel', '제주도 다른 보호자 기억', 'ordinary', now() - interval '1 day', NULL, true);

SELECT ok(NOT has_function_privilege('anon', 'api.guardian_memory_search(uuid,text)', 'EXECUTE'),
    'signed-out role cannot call family search');
SELECT ok(NOT has_function_privilege('service_role', 'api.guardian_memory_search(uuid,text)', 'EXECUTE'),
    'service role has no exposed family-search grant');
SELECT ok(has_function_privilege('authenticated', 'api.guardian_memory_search(uuid,text)', 'EXECUTE'),
    'only authenticated clients can call search');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'api.guardian_memory_search(uuid,text)'::regprocedure),
    'search executes with caller privileges and underlying RLS');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000501', true);
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '제주도')), 1,
    'verified guardian finds only current ordinary owned fact');
SELECT is((SELECT content FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '제주도') LIMIT 1), '수민과 제주도 여행',
    'avoid/sensitive/stale/future/inactive and other author are excluded');
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000602', '제주도')), 0,
    'caller cannot search another patient');
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '%')), 0,
    'wildcard-like input is literal and cannot list all memories');
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '제')), 0,
    'one-character queries are refused');
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', repeat('제', 81))), 0,
    'oversized queries are refused');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000503', true);
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000602', '제주도')), 0,
    'pending guardian has no retrieval access');
RESET ROLE;

UPDATE kof5.patient_guardian_link SET access_status = 'revoked', revoked_at = now()
WHERE patient_id = '00000000-0000-4000-8000-000000000601'
  AND guardian_user_id = '00000000-0000-4000-8000-000000000501';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000501', true);
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '제주도')), 0,
    'link revocation immediately removes retrieval access');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000502', true);
SET ROLE authenticated;
SELECT is((SELECT count(*)::integer FROM api.guardian_memory_search(
    '00000000-0000-4000-8000-000000000601', '제주도')), 1,
    'another verified guardian keeps only their own memory');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
