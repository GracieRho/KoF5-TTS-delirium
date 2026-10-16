-- Uses only existing local synthetic accounts. Every write is rolled back.
BEGIN;
SELECT set_config('test.guardian',(SELECT id::text FROM auth.users WHERE email='guardian@email.com'),true);
SELECT set_config('test.staff',(SELECT id::text FROM auth.users WHERE email='hospital@email.com'),true);
SELECT set_config('test.patient','00000000-0000-4000-8000-000000000976',true);
SELECT set_config('test.encounter',(SELECT encounter_id::text FROM kof5.hospital_encounter WHERE patient_id=current_setting('test.patient')::uuid AND status='in_progress'),true);
SELECT set_config('test.plan',(SELECT schedule_id::text FROM kof5.care_voice_schedule WHERE patient_id=current_setting('test.patient')::uuid AND status='planned' LIMIT 1),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('test.guardian'),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.guardian'),'role','authenticated')::text,true);
DO $$
DECLARE id uuid; again uuid; new_id uuid; payload jsonb:='[{"id":"TEST-memory","title":"산책","category":"story","content":"가상 산책 기억"}]';
 profile jsonb:='{"guardian_name":"가상 보호자","patient_alias":"가상 환자","relationship":"딸","address_as":"아빠"}';
BEGIN
 IF NOT EXISTS(SELECT 1 FROM api.guardian_material_targets() WHERE patient_id=current_setting('test.patient')::uuid) THEN RAISE EXCEPTION 'missing identity'; END IF;
 id:=api.submit_family_material(current_setting('test.patient')::uuid,current_setting('test.encounter')::uuid,profile,payload,'none',repeat('a',64));
 again:=api.submit_family_material(current_setting('test.patient')::uuid,current_setting('test.encounter')::uuid,profile,payload,'none',repeat('a',64));
 IF id<>again THEN RAISE EXCEPTION 'retry duplicated submission'; END IF;
 PERFORM set_config('test.material',id::text,true);
 IF NOT EXISTS(SELECT 1 FROM api.family_material WHERE material_id=id AND memories=payload AND status='pending') THEN RAISE EXCEPTION 'content not persisted'; END IF;
 BEGIN PERFORM api.review_family_material(id,'approved','self review'); RAISE EXCEPTION 'guardian self approved'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM api.submit_family_material(gen_random_uuid(),current_setting('test.encounter')::uuid,profile,payload,'none',repeat('a',64)); RAISE EXCEPTION 'cross patient accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM api.submit_family_material(current_setting('test.patient')::uuid,current_setting('test.encounter')::uuid,profile,'[{}]','none',repeat('a',64)); RAISE EXCEPTION 'malformed accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE api.family_material SET status='approved' WHERE material_id=id; RAISE EXCEPTION 'direct edit allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.staff'),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.staff'),'role','authenticated')::text,true);
DO $$
DECLARE id uuid:=current_setting('test.material')::uuid; plan uuid:=current_setting('test.plan')::uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM api.family_material WHERE material_id=id AND revision>=1) THEN RAISE EXCEPTION 'staff missing submission'; END IF;
 BEGIN PERFORM api.link_family_material_plan(id,plan); RAISE EXCEPTION 'pending material linked'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM api.review_family_material(id,'approved','가상 자료 내용 확인');
 PERFORM api.link_family_material_plan(id,plan);
 IF NOT EXISTS(SELECT 1 FROM api.family_material_plan WHERE schedule_id=plan AND material_id=id) THEN RAISE EXCEPTION 'binding mismatch'; END IF;
 IF (api.care_voice_readiness(current_setting('test.patient')::uuid,current_setting('test.encounter')::uuid)->>'playback_ready')::boolean THEN RAISE EXCEPTION 'review incorrectly enabled playback'; END IF;
 BEGIN PERFORM api.review_family_material(id,'rejected','overwrite'); RAISE EXCEPTION 'review overwritten'; EXCEPTION WHEN serialization_failure THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.guardian'),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.guardian'),'role','authenticated')::text,true);
DO $$
DECLARE new_id uuid;
BEGIN
 new_id:=api.submit_family_material(current_setting('test.patient')::uuid,current_setting('test.encounter')::uuid,
 '{"guardian_name":"가상 보호자","patient_alias":"가상 환자","relationship":"딸","address_as":"아빠"}',
 '[{"id":"TEST-memory","title":"수정","category":"story","content":"가상 수정 기억"}]','none',repeat('a',64));
 IF NOT EXISTS(SELECT 1 FROM api.family_material WHERE material_id=current_setting('test.material')::uuid AND status='superseded') THEN RAISE EXCEPTION 'old approval still current'; END IF;
 IF NOT EXISTS(SELECT 1 FROM api.family_material WHERE material_id=new_id AND status='pending') THEN RAISE EXCEPTION 'new revision not pending'; END IF;
 PERFORM api.withdraw_family_material(new_id);
 IF NOT EXISTS(SELECT 1 FROM api.family_material WHERE material_id=new_id AND status='withdrawn') THEN RAISE EXCEPTION 'withdraw failed'; END IF;
END $$;
-- An unrelated authenticated identity cannot read or mutate another guardian's copy.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-999999999999',true);
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-999999999999","role":"authenticated"}',true);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM api.family_material) OR EXISTS(SELECT 1 FROM api.family_material_plan) OR EXISTS(SELECT 1 FROM api.guardian_material_targets()) THEN RAISE EXCEPTION 'unrelated identity leaked data'; END IF;
 BEGIN PERFORM api.review_family_material(current_setting('test.material')::uuid,'approved','unrelated'); RAISE EXCEPTION 'unrelated review'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
