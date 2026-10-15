CREATE VIEW api.care_patient_access WITH(security_invoker=true) AS
SELECT p.patient_id,e.encounter_id,kof5.care_access(p.patient_id,e.encounter_id,false) AS can_read,
 kof5.care_access(p.patient_id,e.encounter_id,true) AS can_document
FROM kof5.hospital_patient p JOIN kof5.hospital_encounter e ON e.patient_id=p.patient_id
WHERE p.active AND e.status='in_progress';
REVOKE ALL ON api.care_patient_access FROM PUBLIC,anon,service_role;
GRANT SELECT ON api.care_patient_access TO authenticated;

CREATE OR REPLACE FUNCTION kof5.care_voice_readiness(_patient uuid,_encounter uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE _linked boolean;
BEGIN
 IF NOT kof5.care_access(_patient,_encounter,false) THEN
   RETURN jsonb_build_object('authorized',false,'family_linked',false,'playback_ready',false,'encounter_active',false,'reason','돌봄 작성 자격과 담당 배정 확인 필요');
 END IF;
 SELECT EXISTS(SELECT 1 FROM kof5.patient_guardian_link WHERE patient_id=_patient AND access_status='verified'
  AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now())) INTO _linked;
 RETURN jsonb_build_object('authorized',true,'family_linked',_linked,'playback_ready',false,'reason','동의·복제 음성·환자 기기 재생 연결 확인 전',
   'encounter_active',kof5.care_access(_patient,_encounter,true));
END $$;

CREATE FUNCTION kof5.register_care_admission(_hospital text,_patient_ref text,_name text,_ward text,_room text,_bed text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE _membership uuid; _patient uuid; _encounter uuid;
BEGIN
 IF NOT kof5.registry_approved(_hospital) THEN RAISE insufficient_privilege; END IF;
 SELECT membership_id INTO _membership FROM kof5.hospital_staff_membership
 WHERE auth_user_id=auth.uid() AND hospital_ref=_hospital AND product_role='registrar' AND status='verified'
   AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now());
 IF _membership IS NULL THEN RAISE insufficient_privilege; END IF;
 IF length(trim(_patient_ref)) NOT BETWEEN 1 AND 100 OR length(trim(_name)) NOT BETWEEN 1 AND 100
   OR length(trim(_ward)) NOT BETWEEN 1 AND 80 OR length(trim(_room)) NOT BETWEEN 1 AND 80 OR length(trim(_bed)) NOT BETWEEN 1 AND 80
   OR _patient_ref IS NULL OR _name IS NULL OR _ward IS NULL OR _room IS NULL OR _bed IS NULL THEN
   RAISE EXCEPTION '환자와 입원 정보를 확인해주세요' USING ERRCODE='23514';
 END IF;
 INSERT INTO kof5.hospital_patient(hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
 VALUES(_hospital,trim(_patient_ref),trim(_name),auth.uid()::text) RETURNING patient_id INTO _patient;
 INSERT INTO kof5.hospital_encounter(patient_id,ehr_encounter_ref,status,admitted_at,ward_ref,room_ref,bed_ref,location_verified_at)
 VALUES(_patient,'PORTAL-'||gen_random_uuid()::text,'in_progress',now(),trim(_ward),trim(_room),trim(_bed),now()) RETURNING encounter_id INTO _encounter;
 -- Registration does not grant clinical authority. Only an already authorized
 -- care documenter can receive a new assignment in the same institution.
 IF EXISTS(SELECT 1 FROM kof5.care_staff_authorization WHERE auth_user_id=auth.uid() AND hospital_ref=_hospital
  AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now())) THEN
  INSERT INTO kof5.hospital_staff_assignment(membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
  VALUES(_membership,_hospital,_patient,'verified',now(),auth.uid()::text,now());
 END IF;
 RETURN _patient;
END $$;
REVOKE ALL ON FUNCTION kof5.register_care_admission(text,text,text,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION kof5.register_care_admission(text,text,text,text,text,text) TO authenticated;
CREATE FUNCTION api.register_care_admission(_hospital text,_patient_ref text,_name text,_ward text,_room text,_bed text) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT kof5.register_care_admission(_hospital,_patient_ref,_name,_ward,_room,_bed); $$;
REVOKE ALL ON FUNCTION api.register_care_admission(text,text,text,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION api.register_care_admission(text,text,text,text,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
