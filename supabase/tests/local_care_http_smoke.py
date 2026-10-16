"""Actual local care CRUD/RLS/audit checks; temporary synthetic institution only."""
import json
import secrets
from urllib.error import HTTPError
from urllib.request import Request,urlopen
from uuid import UUID,uuid4
from local_http_smoke import local_keys,verify_local_target,request,sql

def main():
 keys=local_keys();verify_local_target(keys)
 url,public,admin=keys['API_URL'],keys['PUBLISHABLE_KEY'],keys['SERVICE_ROLE_KEY']
 patient,other,encounter,other_encounter,membership=(str(uuid4()) for _ in range(5))
 hospital='TEST-CARE-'+uuid4().hex[:12];email='care-'+uuid4().hex+'@example.invalid';password=secrets.token_urlsafe(24)
 status,user=request(url+'/auth/v1/admin/users','POST',admin,payload={'email':email,'password':password,'email_confirm':True});assert status in (200,201)
 uid=str(UUID(user['id']));created_patient=None;token=None
 def call(table,method='GET',body=None,query=''):
  headers={'apikey':public,'Authorization':'Bearer '+token,'Content-Profile':'api','Accept-Profile':'api','Prefer':'return=representation','Content-Type':'application/json'}
  req=Request(url+'/rest/v1/'+table+query,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
  try:response=urlopen(req,timeout=10)
  except HTTPError as error:response=error
  with response:
   data=response.read();return response.status,json.loads(data) if data else None
 try:
  sql(f"""BEGIN;
  INSERT INTO kof5.hospital_patient(patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
  VALUES('{patient}','{hospital}','TEST-1','시험환자1','TEST'),('{other}','{hospital}','TEST-2','시험환자2','TEST');
  INSERT INTO kof5.hospital_encounter(encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
  VALUES('{encounter}','{patient}','TEST-ENC-1','in_progress',now()),('{other_encounter}','{other}','TEST-ENC-2','in_progress',now());
  INSERT INTO kof5.hospital_staff_membership(membership_id,auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
  VALUES('{membership}','{uid}','{hospital}','registrar','verified',now()-interval '1 minute','TEST',now());
  COMMIT;""")
  status,session=request(url+'/auth/v1/token?grant_type=password','POST',public,payload={'email':email,'password':password});assert status==200;token=session['access_token']
  base={'patient_id':patient,'encounter_id':encounter}
  note={**base,'kind':'observation','summary':'가상 관찰 기록'}
  # Registrar read alone never grants care documentation.
  status,rows=call('hospital_patient_list');assert status==200 and len(rows)==2
  assert call('care_note','POST',note)[0] in (401,403)
  sql(f"""INSERT INTO kof5.care_staff_authorization(auth_user_id,hospital_ref,approval_ref) VALUES('{uid}','{hospital}','TEST-CARE');
  INSERT INTO kof5.hospital_staff_assignment(membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
  VALUES('{membership}','{hospital}','{patient}','verified',now()-interval '1 minute','TEST',now());""")
  status,rows=call('care_note','POST',note);assert status==201,(status,rows);note_id=rows[0]['note_id'];assert rows[0]['created_by']==uid
  for payload in [{**note,'patient_id':other,'encounter_id':other_encounter},{**note,'encounter_id':other_encounter}]:
   assert call('care_note','POST',payload)[0] in (400,401,403)
  for recipient in [None,'','   ']:
   assert call('care_note','POST',{**note,'kind':'handoff','recipient':recipient})[0]==400
  assert call('care_note','POST',{**note,'kind':'assessment','tool':'4AT','result':'positive','score':13})[0]==400
  assert call('care_note','POST',{**note,'kind':'assessment','tool':'CAM-ICU','result':'positive','care_setting':'ward'})[0]==400
  assert call('care_note','PATCH',{'summary':'overwrite'},'?note_id=eq.'+note_id)[0] in (401,403)
  assert call('care_note','DELETE',None,'?note_id=eq.'+note_id)[0] in (401,403)
  task={**base,'category':'sensory','title':'보청기 확인','owner_label':'TEST 병동팀','due_at':'2026-10-16T00:00:00Z'}
  status,rows=call('care_task','POST',task);assert status==201,(status,rows);task_id=rows[0]['task_id']
  status,rows=call('care_task','PATCH',{'status':'held','outcome':'담당자 확인 중'},f'?task_id=eq.{task_id}&version=eq.1');assert status==200 and len(rows)==1 and rows[0]['version']==2
  status,rows=call('care_task','PATCH',{'status':'completed','outcome':'stale'},f'?task_id=eq.{task_id}&version=eq.1');assert status==200 and rows==[]
  status,rows=call('care_task','PATCH',{'status':'completed','outcome':'확인 완료','due_at':'2026-10-17T00:00:00Z'},f'?task_id=eq.{task_id}&version=eq.2');assert status==200 and rows[0]['completed_at'] and rows[0]['version']==3
  status,logs=call('care_activity',query='?entity_id=eq.'+task_id);assert status==200 and len(logs)==3
  assert any('2026-10-16' in row['detail'] and '2026-10-17' in row['detail'] for row in logs)
  plan={**base,'purpose':'orientation','script':'가상 장소 안내','scheduled_at':'2026-10-16T03:00:00Z','duration_minutes':3,'owner_label':'TEST'}
  status,rows=call('care_voice_schedule','POST',plan);assert status==201,(status,rows);plan_id=rows[0]['schedule_id']
  assert rows[0]['status']=='planned'
  status,ready=call('rpc/care_voice_readiness','POST',{'_patient':patient,'_encounter':encounter});assert status==200 and not ready['playback_ready']
  assert call('care_voice_schedule','PATCH',{'status':'delivered'},f'?schedule_id=eq.{plan_id}&version=eq.1')[0]==400
  status,rows=call('care_voice_schedule','PATCH',{'status':'cancelled','cancel_reason':'수면 우선'},f'?schedule_id=eq.{plan_id}&version=eq.1');assert status==200 and rows[0]['status']=='cancelled'
  # Current admission is checked for writes, historic records remain readable.
  sql(f"UPDATE kof5.hospital_encounter SET status='finished',discharged_at=now() WHERE encounter_id='{encounter}';")
  assert call('care_note','POST',note)[0] in (401,403)
  # Admission RPC requires actual institution activation and registrar authority.
  payload={'_hospital':hospital,'_patient_ref':'TEST-NEW','_name':'새가상환자','_ward':'시험병동','_room':'301','_bed':'1'}
  assert call('rpc/register_care_admission','POST',payload)[0] in (401,403)
  sql(f"INSERT INTO kof5.hospital_registry_activation(hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at) VALUES('{hospital}','approved','TEST','TEST',now());")
  status,created_patient=call('rpc/register_care_admission','POST',payload);assert status==200,(status,created_patient)
  created_patient=str(UUID(created_patient))
  status,rows=call('hospital_patient_list',query='?patient_id=eq.'+created_patient);assert status==200 and len(rows)==1 and rows[0]['encounter_id']
  assert call('rpc/register_care_admission','POST',payload)[0]==409
  status,_=request(url+'/auth/v1/logout?scope=local','POST',public,token);assert status==204
  assert call('care_task')[0]==401
  print('Care local Auth/RLS/assigned authority, immutable notes, recipient/score validation, task CAS/audit, plan cancellation, admission gate/atomicity, logout: PASS')
 finally:
  sql(f"""BEGIN;
  DELETE FROM kof5.care_activity WHERE patient_id IN (SELECT patient_id FROM kof5.hospital_patient WHERE hospital_ref='{hospital}');
  DELETE FROM kof5.care_note WHERE patient_id IN (SELECT patient_id FROM kof5.hospital_patient WHERE hospital_ref='{hospital}');
  DELETE FROM kof5.care_task WHERE patient_id IN (SELECT patient_id FROM kof5.hospital_patient WHERE hospital_ref='{hospital}');
  DELETE FROM kof5.care_voice_schedule WHERE patient_id IN (SELECT patient_id FROM kof5.hospital_patient WHERE hospital_ref='{hospital}');
  DELETE FROM kof5.hospital_staff_assignment WHERE membership_id='{membership}';
  DELETE FROM kof5.care_staff_authorization WHERE auth_user_id='{uid}';
  DELETE FROM kof5.hospital_staff_membership WHERE membership_id='{membership}';
  DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{hospital}';
  DELETE FROM kof5.hospital_encounter WHERE patient_id IN (SELECT patient_id FROM kof5.hospital_patient WHERE hospital_ref='{hospital}');
  DELETE FROM kof5.hospital_patient WHERE hospital_ref='{hospital}';
  COMMIT;""")
  status,_=request(url+'/auth/v1/admin/users/'+uid,'DELETE',admin);assert status in (200,204)
if __name__=='__main__':main()
