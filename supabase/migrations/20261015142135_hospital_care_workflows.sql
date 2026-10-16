-- Care documentation is separate from registrar access and device playback.
CREATE TABLE kof5.care_staff_authorization (
 auth_user_id uuid NOT NULL REFERENCES auth.users(id), hospital_ref text NOT NULL,
 approval_ref text NOT NULL CHECK(length(trim(approval_ref))>0),
 effective_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz,
 PRIMARY KEY(auth_user_id,hospital_ref), CHECK(expires_at IS NULL OR expires_at>effective_at)
);
ALTER TABLE kof5.care_staff_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.care_staff_authorization FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.care_staff_authorization FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION kof5.care_access(_patient uuid,_encounter uuid,_write boolean DEFAULT false) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS (
  SELECT 1 FROM kof5.hospital_patient p
  JOIN kof5.hospital_encounter e ON e.patient_id=p.patient_id AND e.encounter_id=_encounter
  JOIN kof5.hospital_staff_membership m ON m.hospital_ref=p.hospital_ref AND m.auth_user_id=auth.uid()
  JOIN kof5.care_staff_authorization c ON c.auth_user_id=m.auth_user_id AND c.hospital_ref=m.hospital_ref
  JOIN kof5.hospital_staff_assignment a ON a.membership_id=m.membership_id AND a.patient_id=p.patient_id
  WHERE p.patient_id=_patient AND p.active AND m.status='verified' AND m.effective_at<=now()
    AND (m.expires_at IS NULL OR m.expires_at>now()) AND a.status='verified' AND a.effective_at<=now()
    AND (a.expires_at IS NULL OR a.expires_at>now()) AND c.effective_at<=now()
    AND (c.expires_at IS NULL OR c.expires_at>now()) AND (NOT _write OR e.status='in_progress')
 );
$$;
REVOKE ALL ON FUNCTION kof5.care_access(uuid,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION kof5.care_access(uuid,uuid,boolean) TO authenticated;

CREATE TABLE kof5.care_note (
 note_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), patient_id uuid NOT NULL, encounter_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('assessment','observation','handoff','concern','resolution','correction')),
 summary text NOT NULL CHECK(length(trim(summary)) BETWEEN 1 AND 2000),
 tool text CHECK(tool IN ('4AT','CAM-ICU','ICDSC')),
 care_setting text NOT NULL DEFAULT 'ward' CHECK(care_setting IN ('ward','icu')),
 result text NOT NULL DEFAULT 'not_applicable' CHECK(result IN ('not_applicable','negative','positive','unable')),
 score integer, severity text NOT NULL DEFAULT 'routine' CHECK(severity IN ('routine','attention','urgent')),
 recipient text CHECK(length(recipient)<=100), related_note_id uuid REFERENCES kof5.care_note(note_id),
 observed_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 FOREIGN KEY(encounter_id,patient_id) REFERENCES kof5.hospital_encounter(encounter_id,patient_id),
 CHECK((kind='assessment' AND tool IS NOT NULL AND result<>'not_applicable') OR (kind<>'assessment' AND tool IS NULL AND score IS NULL AND result='not_applicable')),
 CHECK(score IS NULL OR (tool='4AT' AND score BETWEEN 0 AND 12) OR (tool='ICDSC' AND score BETWEEN 0 AND 8)),
 CHECK(result<>'unable' OR score IS NULL),
 CHECK((kind IN ('resolution','correction'))=(related_note_id IS NOT NULL)),
 CONSTRAINT care_handoff_recipient_required CHECK(kind<>'handoff' OR (recipient IS NOT NULL AND length(trim(recipient))>0)),
 CHECK(tool IS NULL OR (care_setting='ward' AND tool='4AT') OR (care_setting='icu' AND tool IN ('CAM-ICU','ICDSC')))
);
CREATE UNIQUE INDEX care_note_one_resolution ON kof5.care_note(related_note_id) WHERE kind='resolution';
CREATE INDEX care_note_encounter ON kof5.care_note(patient_id,encounter_id,observed_at DESC);

CREATE TABLE kof5.care_task (
 task_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), patient_id uuid NOT NULL, encounter_id uuid NOT NULL,
 category text NOT NULL CHECK(category IN ('orientation','family','sensory','sleep','nutrition','mobility','clinical_review')),
 title text NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 160),
 owner_label text NOT NULL CHECK(length(trim(owner_label)) BETWEEN 1 AND 100), due_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','completed','held')),
 outcome text NOT NULL DEFAULT '' CHECK(length(outcome)<=1000),
 created_at timestamptz NOT NULL DEFAULT now(), created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT now(), updated_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 version integer NOT NULL DEFAULT 1, completed_at timestamptz,
 FOREIGN KEY(encounter_id,patient_id) REFERENCES kof5.hospital_encounter(encounter_id,patient_id),
 CHECK(status<>'held' OR length(trim(outcome))>0), CHECK((status='completed')=(completed_at IS NOT NULL))
);
CREATE INDEX care_task_encounter ON kof5.care_task(patient_id,encounter_id,due_at);

CREATE TABLE kof5.care_voice_schedule (
 schedule_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), patient_id uuid NOT NULL, encounter_id uuid NOT NULL,
 purpose text NOT NULL CHECK(purpose IN ('orientation','reassurance','family_story')),
 script text NOT NULL CHECK(length(trim(script)) BETWEEN 1 AND 1000),
 scheduled_at timestamptz NOT NULL, duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 15),
 owner_label text NOT NULL CHECK(length(trim(owner_label)) BETWEEN 1 AND 100),
 status text NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','cancelled')),
 cancel_reason text CHECK(length(trim(cancel_reason)) BETWEEN 1 AND 1000),
 created_at timestamptz NOT NULL DEFAULT now(), created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT now(), updated_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 version integer NOT NULL DEFAULT 1,
 FOREIGN KEY(encounter_id,patient_id) REFERENCES kof5.hospital_encounter(encounter_id,patient_id),
 CHECK((status='cancelled')=(cancel_reason IS NOT NULL))
);
CREATE INDEX care_voice_schedule_encounter ON kof5.care_voice_schedule(patient_id,encounter_id,scheduled_at);

CREATE TABLE kof5.care_activity (
 activity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), patient_id uuid NOT NULL, encounter_id uuid NOT NULL,
 entity text NOT NULL, entity_id uuid NOT NULL, action text NOT NULL,
 detail text NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY(encounter_id,patient_id) REFERENCES kof5.hospital_encounter(encounter_id,patient_id)
);
CREATE INDEX care_activity_encounter ON kof5.care_activity(patient_id,encounter_id,recorded_at DESC);

CREATE FUNCTION kof5.care_record_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF TG_OP='INSERT' THEN
   NEW.created_at=now(); NEW.created_by=auth.uid();
   IF TG_TABLE_NAME='care_note' THEN
     IF NEW.observed_at>now()+interval '5 minutes' OR NEW.observed_at<now()-interval '30 days' THEN
       RAISE EXCEPTION '관찰 시각은 최근 30일 안이어야 합니다' USING ERRCODE='23514';
     END IF;
     IF NEW.related_note_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM kof5.care_note n WHERE n.note_id=NEW.related_note_id
       AND n.patient_id=NEW.patient_id AND n.encounter_id=NEW.encounter_id
       AND (NEW.kind='correction' OR n.kind='concern')) THEN
       RAISE EXCEPTION '같은 입원의 원본 기록이 필요합니다' USING ERRCODE='23514';
     END IF;
     RETURN NEW;
   END IF;
 ELSE
   IF NEW.patient_id<>OLD.patient_id OR NEW.encounter_id<>OLD.encounter_id OR NEW.created_by<>OLD.created_by OR NEW.created_at<>OLD.created_at THEN
     RAISE EXCEPTION '기록 소유권은 변경할 수 없습니다' USING ERRCODE='23514';
   END IF;
   IF TG_TABLE_NAME='care_voice_schedule' AND OLD.status='cancelled' THEN
     RAISE EXCEPTION '취소된 일정은 변경할 수 없습니다' USING ERRCODE='23514';
   END IF;
   NEW.version=OLD.version+1;
 END IF;
 NEW.updated_at=now(); NEW.updated_by=auth.uid();
 IF TG_TABLE_NAME='care_task' THEN NEW.completed_at=CASE WHEN NEW.status='completed' THEN now() ELSE NULL END; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.care_record_guard() FROM PUBLIC;

CREATE FUNCTION kof5.care_record_activity() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE _id uuid; _detail text;
BEGIN
 IF TG_TABLE_NAME='care_note' THEN _id=NEW.note_id; _detail=NEW.kind || ': ' || NEW.summary;
 ELSIF TG_TABLE_NAME='care_task' THEN _id=NEW.task_id; _detail=NEW.title || ' · ' || NEW.status || ' · 기한 ' || NEW.due_at::text || CASE WHEN TG_OP='UPDATE' THEN ' (이전 ' || OLD.due_at::text || ', ' || OLD.status || ')' ELSE '' END || ' · ' || NEW.outcome;
 ELSE _id=NEW.schedule_id; _detail=NEW.purpose || ' · ' || NEW.status || ' ' || COALESCE(NEW.cancel_reason,''); END IF;
 INSERT INTO kof5.care_activity(patient_id,encounter_id,entity,entity_id,action,detail,actor_id)
 VALUES(NEW.patient_id,NEW.encounter_id,TG_TABLE_NAME,_id,TG_OP,_detail,auth.uid());
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION kof5.care_record_activity() FROM PUBLIC;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['care_note','care_task','care_voice_schedule','care_activity'] LOOP
  EXECUTE format('ALTER TABLE kof5.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE kof5.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON kof5.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('CREATE POLICY care_read ON kof5.%I FOR SELECT TO authenticated USING(kof5.care_access(patient_id,encounter_id,false))',t);
  EXECUTE format('GRANT SELECT ON kof5.%I TO authenticated',t);
  EXECUTE format('CREATE VIEW api.%I WITH(security_invoker=true) AS SELECT * FROM kof5.%I',t,t);
  EXECUTE format('REVOKE ALL ON api.%I FROM PUBLIC,anon,service_role',t);
  EXECUTE format('GRANT SELECT ON api.%I TO authenticated',t);
  IF t<>'care_activity' THEN
   EXECUTE format('CREATE POLICY care_write ON kof5.%I FOR INSERT TO authenticated WITH CHECK(created_by=auth.uid() AND kof5.care_access(patient_id,encounter_id,true))',t);
   EXECUTE format('CREATE TRIGGER care_guard BEFORE INSERT OR UPDATE ON kof5.%I FOR EACH ROW EXECUTE FUNCTION kof5.care_record_guard()',t);
   EXECUTE format('CREATE TRIGGER care_audit AFTER INSERT OR UPDATE ON kof5.%I FOR EACH ROW EXECUTE FUNCTION kof5.care_record_activity()',t);
  END IF;
 END LOOP;
END $$;
GRANT INSERT(patient_id,encounter_id,kind,summary,tool,care_setting,result,score,severity,recipient,related_note_id,observed_at) ON kof5.care_note,api.care_note TO authenticated;
GRANT INSERT(patient_id,encounter_id,category,title,owner_label,due_at) ON kof5.care_task,api.care_task TO authenticated;
GRANT INSERT(patient_id,encounter_id,purpose,script,scheduled_at,duration_minutes,owner_label) ON kof5.care_voice_schedule,api.care_voice_schedule TO authenticated;
CREATE POLICY care_task_update ON kof5.care_task FOR UPDATE TO authenticated
 USING(kof5.care_access(patient_id,encounter_id,true)) WITH CHECK(kof5.care_access(patient_id,encounter_id,true));
CREATE POLICY care_schedule_update ON kof5.care_voice_schedule FOR UPDATE TO authenticated
 USING(kof5.care_access(patient_id,encounter_id,true)) WITH CHECK(kof5.care_access(patient_id,encounter_id,true));
GRANT UPDATE(status,outcome,due_at) ON kof5.care_task,api.care_task TO authenticated;
GRANT UPDATE(status,cancel_reason) ON kof5.care_voice_schedule,api.care_voice_schedule TO authenticated;

-- No execution or delivery claim: readiness is read fresh and fails closed.
CREATE FUNCTION kof5.care_voice_readiness(_patient uuid,_encounter uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE _linked boolean;
BEGIN
 IF NOT kof5.care_access(_patient,_encounter,false) THEN RAISE insufficient_privilege; END IF;
 SELECT EXISTS(SELECT 1 FROM kof5.patient_guardian_link WHERE patient_id=_patient AND access_status='verified'
  AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now())) INTO _linked;
 RETURN jsonb_build_object('family_linked',_linked,'playback_ready',false,'reason','동의·복제 음성·환자 기기 재생 연결 확인 전',
   'encounter_active',EXISTS(SELECT 1 FROM kof5.hospital_encounter WHERE encounter_id=_encounter AND patient_id=_patient AND status='in_progress'));
END $$;
REVOKE ALL ON FUNCTION kof5.care_voice_readiness(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION kof5.care_voice_readiness(uuid,uuid) TO authenticated;
CREATE FUNCTION api.care_voice_readiness(_patient uuid,_encounter uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path='' AS $$ SELECT kof5.care_voice_readiness(_patient,_encounter); $$;
REVOKE ALL ON FUNCTION api.care_voice_readiness(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION api.care_voice_readiness(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
