-- Immutable guardian submissions; review is distinct from playback authorization.
CREATE TABLE kof5.family_material (
 material_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 patient_id uuid NOT NULL REFERENCES kof5.hospital_patient,
 encounter_id uuid NOT NULL REFERENCES kof5.hospital_encounter,
 guardian_user_id uuid NOT NULL REFERENCES auth.users,
 revision integer NOT NULL,
 content_hash text NOT NULL,
 profile jsonb NOT NULL,
 memories jsonb NOT NULL,
 voice_status text NOT NULL,
 voice_revision text NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','withdrawn','superseded')),
 submitted_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz, reviewed_by uuid REFERENCES auth.users, review_note text NOT NULL DEFAULT '',
 UNIQUE(patient_id,encounter_id,guardian_user_id,revision)
);
CREATE TABLE kof5.family_material_plan (
 schedule_id uuid PRIMARY KEY REFERENCES kof5.care_voice_schedule,
 material_id uuid NOT NULL REFERENCES kof5.family_material,
 linked_by uuid NOT NULL DEFAULT auth.uid(), linked_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE kof5.family_material ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_material FORCE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_material_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.family_material_plan FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.family_material,kof5.family_material_plan FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION kof5.guardian_material_access(_patient uuid,_encounter uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM kof5.patient_guardian_link l JOIN kof5.hospital_encounter e ON e.patient_id=l.patient_id
 WHERE l.patient_id=_patient AND e.encounter_id=_encounter AND e.status='in_progress'
 AND l.guardian_user_id=auth.uid() AND l.access_status='verified' AND l.effective_at<=now()
 AND (l.expires_at IS NULL OR l.expires_at>now()));
$$;
REVOKE ALL ON FUNCTION kof5.guardian_material_access(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION kof5.guardian_material_access(uuid,uuid) TO authenticated;
CREATE POLICY material_read ON kof5.family_material FOR SELECT TO authenticated USING
 ((guardian_user_id=auth.uid() AND kof5.guardian_material_access(patient_id,encounter_id)) OR kof5.care_access(patient_id,encounter_id,false));
CREATE POLICY material_plan_read ON kof5.family_material_plan FOR SELECT TO authenticated USING
 (EXISTS(SELECT 1 FROM kof5.family_material m WHERE m.material_id=family_material_plan.material_id));
GRANT SELECT ON kof5.family_material,kof5.family_material_plan TO authenticated;
CREATE VIEW api.family_material WITH(security_invoker=true) AS SELECT * FROM kof5.family_material;
CREATE VIEW api.family_material_plan WITH(security_invoker=true) AS SELECT * FROM kof5.family_material_plan;
REVOKE ALL ON api.family_material,api.family_material_plan FROM PUBLIC,anon,service_role;
GRANT SELECT ON api.family_material,api.family_material_plan TO authenticated;

-- Deliberately returns only the linked patient's display identity and current admission.
CREATE FUNCTION kof5.guardian_material_targets() RETURNS TABLE(patient_id uuid,encounter_id uuid,patient_name text,hospital_ref text,relationship text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p.patient_id,e.encounter_id,p.staff_display_name,p.hospital_ref,l.relationship
 FROM kof5.patient_guardian_link l JOIN kof5.hospital_patient p ON p.patient_id=l.patient_id
 JOIN kof5.hospital_encounter e ON e.patient_id=p.patient_id
 WHERE p.active AND kof5.guardian_material_access(p.patient_id,e.encounter_id) AND l.guardian_user_id=auth.uid();
$$;
CREATE FUNCTION kof5.submit_family_material(_patient uuid,_encounter uuid,_profile jsonb,_memories jsonb,_voice_status text,_voice_revision text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE _hash text; _id uuid; _revision integer; _memory jsonb; _field text;
BEGIN
 IF NOT kof5.guardian_material_access(_patient,_encounter) THEN RAISE insufficient_privilege; END IF;
 IF jsonb_typeof(_profile) IS DISTINCT FROM 'object' OR jsonb_typeof(_memories) IS DISTINCT FROM 'array'
 OR octet_length(_profile::text)>2000 OR octet_length(_memories::text)>180000 OR jsonb_array_length(_memories) NOT BETWEEN 1 AND 30
 OR _voice_status IS NULL OR _voice_status NOT IN ('none','failed','pending','verification_pending','created','deletion_pending','deleted')
 OR _voice_revision IS NULL OR _voice_revision !~ '^[a-f0-9]{64}$' THEN RAISE check_violation; END IF;
 FOREACH _field IN ARRAY ARRAY['guardian_name','patient_alias','relationship','address_as'] LOOP
  IF jsonb_typeof(_profile->_field) IS DISTINCT FROM 'string' OR length(trim(_profile->>_field)) NOT BETWEEN 1 AND 40 THEN RAISE check_violation; END IF;
 END LOOP;
 FOR _memory IN SELECT value FROM jsonb_array_elements(_memories) LOOP
  IF jsonb_typeof(_memory) IS DISTINCT FROM 'object' OR jsonb_typeof(_memory->'id') IS DISTINCT FROM 'string'
  OR jsonb_typeof(_memory->'title') IS DISTINCT FROM 'string' OR length(trim(_memory->>'title')) NOT BETWEEN 1 AND 80
  OR jsonb_typeof(_memory->'content') IS DISTINCT FROM 'string' OR length(trim(_memory->>'content')) NOT BETWEEN 1 AND 1200
  OR (_memory->>'category') IS NULL OR (_memory->>'category') NOT IN ('family','story','comfort','avoid') THEN RAISE check_violation; END IF;
 END LOOP;
 -- Lock the admission to serialize revision allocation and concurrent re-submission.
 PERFORM 1 FROM kof5.hospital_encounter WHERE encounter_id=_encounter FOR UPDATE;
 _hash:=encode(extensions.digest(convert_to(jsonb_build_array(_profile,_memories,_voice_status,_voice_revision)::text,'UTF8'),'sha256'),'hex');
 SELECT material_id INTO _id FROM kof5.family_material WHERE patient_id=_patient AND encounter_id=_encounter
 AND guardian_user_id=auth.uid() AND content_hash=_hash AND status IN ('pending','approved') ORDER BY revision DESC LIMIT 1;
 IF _id IS NOT NULL THEN RETURN _id; END IF;
 SELECT coalesce(max(revision),0)+1 INTO _revision FROM kof5.family_material
 WHERE patient_id=_patient AND encounter_id=_encounter AND guardian_user_id=auth.uid();
 UPDATE kof5.family_material SET status='superseded' WHERE patient_id=_patient AND encounter_id=_encounter
 AND guardian_user_id=auth.uid() AND status IN ('pending','approved');
 INSERT INTO kof5.family_material(patient_id,encounter_id,guardian_user_id,revision,content_hash,profile,memories,voice_status,voice_revision)
 VALUES(_patient,_encounter,auth.uid(),_revision,_hash,_profile,_memories,_voice_status,_voice_revision) RETURNING material_id INTO _id;
 RETURN _id;
END $$;
CREATE FUNCTION kof5.review_family_material(_id uuid,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m kof5.family_material;
BEGIN
 SELECT * INTO m FROM kof5.family_material WHERE material_id=_id FOR UPDATE;
 IF NOT FOUND OR NOT kof5.care_access(m.patient_id,m.encounter_id,true) OR m.guardian_user_id=auth.uid()
 OR NOT EXISTS(SELECT 1 FROM kof5.patient_guardian_link l WHERE l.patient_id=m.patient_id AND l.guardian_user_id=m.guardian_user_id
 AND l.access_status='verified' AND l.effective_at<=now() AND (l.expires_at IS NULL OR l.expires_at>now())) THEN RAISE insufficient_privilege; END IF;
 IF m.status<>'pending' THEN RAISE EXCEPTION '자료 상태가 변경되었습니다. 다시 조회해주세요.' USING ERRCODE='40001'; END IF;
 IF _decision IS NULL OR _decision NOT IN ('approved','rejected') OR _note IS NULL OR length(trim(_note)) NOT BETWEEN 1 AND 500 THEN RAISE check_violation; END IF;
 UPDATE kof5.family_material SET status=_decision,review_note=trim(_note),reviewed_by=auth.uid(),reviewed_at=now() WHERE material_id=_id;
END $$;
CREATE FUNCTION kof5.withdraw_family_material(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m kof5.family_material;
BEGIN
 SELECT * INTO m FROM kof5.family_material WHERE material_id=_id FOR UPDATE;
 IF NOT FOUND OR m.guardian_user_id<>auth.uid() OR NOT kof5.guardian_material_access(m.patient_id,m.encounter_id) THEN RAISE insufficient_privilege; END IF;
 UPDATE kof5.family_material SET status='withdrawn' WHERE material_id=_id AND status IN ('pending','approved');
END $$;
CREATE FUNCTION kof5.link_family_material_plan(_id uuid,_schedule uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m kof5.family_material; p kof5.care_voice_schedule;
BEGIN
 SELECT * INTO m FROM kof5.family_material WHERE material_id=_id FOR UPDATE;
 SELECT * INTO p FROM kof5.care_voice_schedule WHERE schedule_id=_schedule FOR UPDATE;
 IF m.material_id IS NULL OR p.schedule_id IS NULL OR NOT kof5.care_access(m.patient_id,m.encounter_id,true)
 OR m.patient_id<>p.patient_id OR m.encounter_id<>p.encounter_id THEN RAISE insufficient_privilege; END IF;
 IF m.status<>'approved' OR p.status<>'planned' OR NOT EXISTS(SELECT 1 FROM kof5.patient_guardian_link l
 WHERE l.patient_id=m.patient_id AND l.guardian_user_id=m.guardian_user_id AND l.access_status='verified'
 AND l.effective_at<=now() AND (l.expires_at IS NULL OR l.expires_at>now())) THEN RAISE check_violation; END IF;
 INSERT INTO kof5.family_material_plan(schedule_id,material_id) VALUES(_schedule,_id)
 ON CONFLICT(schedule_id) DO UPDATE SET material_id=excluded.material_id,linked_by=auth.uid(),linked_at=now();
END $$;

CREATE FUNCTION api.guardian_material_targets() RETURNS TABLE(patient_id uuid,encounter_id uuid,patient_name text,hospital_ref text,relationship text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM kof5.guardian_material_targets(); $$;
CREATE FUNCTION api.submit_family_material(_patient uuid,_encounter uuid,_profile jsonb,_memories jsonb,_voice_status text,_voice_revision text) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT kof5.submit_family_material(_patient,_encounter,_profile,_memories,_voice_status,_voice_revision); $$;
CREATE FUNCTION api.review_family_material(_id uuid,_decision text,_note text) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT kof5.review_family_material(_id,_decision,_note); $$;
CREATE FUNCTION api.withdraw_family_material(_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT kof5.withdraw_family_material(_id); $$;
CREATE FUNCTION api.link_family_material_plan(_id uuid,_schedule uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT kof5.link_family_material_plan(_id,_schedule); $$;
REVOKE ALL ON FUNCTION kof5.guardian_material_targets(),api.guardian_material_targets(),
 kof5.submit_family_material(uuid,uuid,jsonb,jsonb,text,text),api.submit_family_material(uuid,uuid,jsonb,jsonb,text,text),
 kof5.review_family_material(uuid,text,text),api.review_family_material(uuid,text,text),
 kof5.withdraw_family_material(uuid),api.withdraw_family_material(uuid),
 kof5.link_family_material_plan(uuid,uuid),api.link_family_material_plan(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION kof5.guardian_material_targets(),api.guardian_material_targets(),
 kof5.submit_family_material(uuid,uuid,jsonb,jsonb,text,text),api.submit_family_material(uuid,uuid,jsonb,jsonb,text,text),
 kof5.review_family_material(uuid,text,text),api.review_family_material(uuid,text,text),
 kof5.withdraw_family_material(uuid),api.withdraw_family_material(uuid),
 kof5.link_family_material_plan(uuid,uuid),api.link_family_material_plan(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
