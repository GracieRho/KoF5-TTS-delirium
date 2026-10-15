"""작업 전용 가상 병원의 돌봄 업무 자료. 실제 임상 자격을 발급하지 않는다."""
import json
import subprocess
from seed_portal import identifier, literal, HOSPITAL, PATIENT
from local_http_smoke import ROOT, local_keys, sql, verify_local_target
from uuid import UUID

def main():
 verify_local_target(local_keys())
 user=str(UUID(sql("SELECT id FROM auth.users WHERE email='hospital@email.com'")))
 fixture=json.loads((ROOT/'supabase/fixtures/portal.json').read_text())
 statements=['BEGIN;',f"SELECT set_config('request.jwt.claims', {literal(json.dumps({'sub':user,'role':'authenticated'}))},true);"]
 statements.append(f"""INSERT INTO kof5.hospital_registry_activation(hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at,expires_at)
 VALUES('{HOSPITAL}','approved','TEST-LOCAL-INSTITUTION','TEST-LOCAL-CARE-WORKFLOW',now(),now()+interval '30 days') ON CONFLICT DO NOTHING;""")
 statements.append(f"""INSERT INTO kof5.care_staff_authorization(auth_user_id,hospital_ref,approval_ref,effective_at,expires_at)
 VALUES('{user}','{HOSPITAL}','TEST-LOCAL-CARE-DOCUMENTATION',now()-interval '1 minute',now()+interval '30 days') ON CONFLICT DO NOTHING;""")
 task_rows=[('orientation','날짜·장소와 담당자를 천천히 안내','completed'),('sensory','안경·보청기 준비와 착용 상태 확인','open'),('nutrition','섭취 상태와 수분 제한 여부를 담당자와 확인','open'),('mobility','허용된 활동 범위와 이동 지원 확인','open'),('sleep','야간 소음·조명과 휴식 시간 확인','open'),('family','가족 면회와 익숙한 주제 확인','open'),('clinical_review','통증·약물·감염 관련 담당자 검토 여부 확인','held')]
 for i,patient in enumerate(fixture['patients']):
  pid=PATIENT if i==0 else identifier(f'patient-{i}');eid=identifier(f'encounter-{i}')
  statements.append(f"""INSERT INTO kof5.hospital_staff_assignment(assignment_id,membership_id,hospital_ref,patient_id,status,effective_at,expires_at,verified_by_staff_ref,verified_at)
  VALUES('{identifier(f'care-assignment-{i}')}','{identifier('membership')}','{HOSPITAL}','{pid}','verified',now()-interval '1 minute',now()+interval '30 days','TEST-VERIFY',now()) ON CONFLICT DO NOTHING;""")
  result=['positive','negative','unable','positive','negative','positive'][i];score=[5,0,None,4,0,6][i]
  summary=['주의 집중 변화가 있어 담당자 재확인 계획을 기록했습니다.','평소 대화 양상과 비교한 평가 결과를 기록했습니다.','평가 중 피로를 표현해 마치지 못했습니다. 휴식 후 재확인 예정입니다.','수면 중 자주 깨어 가족 설명과 환경 확인을 계획했습니다.','가족과의 대화에 참여한 상태를 기록했습니다.','전날보다 반응이 느린 양상이 있어 담당자 확인이 필요합니다.'][i]
  statements.append(f"""INSERT INTO kof5.care_note(note_id,patient_id,encounter_id,kind,summary,tool,result,score,observed_at)
   VALUES('{identifier(f'care-assessment-{i}')}','{pid}','{eid}','assessment',{literal(summary)},'4AT','{result}',{'NULL' if score is None else score},now()-interval '{i+1} hours') ON CONFLICT DO NOTHING;
   INSERT INTO kof5.care_note(note_id,patient_id,encounter_id,kind,summary,recipient,observed_at)
   VALUES('{identifier(f'care-handoff-{i}')}','{pid}','{eid}','handoff',{literal(patient['comfort']+' 다음 근무 때 반응과 편안함을 확인해주세요.')},'다음 근무 담당 간호사',now()-interval '30 minutes') ON CONFLICT DO NOTHING;""")
  if i in (0,3):
   statements.append(f"""INSERT INTO kof5.care_note(note_id,patient_id,encounter_id,kind,summary,severity,observed_at)
   VALUES('{identifier(f'care-concern-{i}')}','{pid}','{eid}','concern','야간 수면 변화와 낯선 환경에 대한 불편감을 담당자가 확인해야 합니다.','attention',now()-interval '20 minutes') ON CONFLICT DO NOTHING;""")
  for j,(category,title,status) in enumerate(task_rows):
   outcome='가상 업무 자료: 수행 내용 확인' if status=='completed' else '담당 의료진 검토 시간 확인 중' if status=='held' else ''
   statements.append(f"""INSERT INTO kof5.care_task(task_id,patient_id,encounter_id,category,title,owner_label,due_at,status,outcome)
   VALUES('{identifier(f'care-task-{i}-{j}')}','{pid}','{eid}','{category}',{literal(title)},'병동팀',now()+interval '{(j-2)*30} minutes','{status}',{literal(outcome)}) ON CONFLICT DO NOTHING;""")
  statements.append(f"""INSERT INTO kof5.care_voice_schedule(schedule_id,patient_id,encounter_id,purpose,script,scheduled_at,duration_minutes,owner_label)
   VALUES('{identifier(f'care-voice-{i}')}','{pid}','{eid}','orientation','지금 계신 장소를 천천히 안내하고 편안한 가족 이야기를 짧게 나눕니다.',(date_trunc('day',now() AT TIME ZONE 'Asia/Seoul')+interval '1 day {9+i} hours') AT TIME ZONE 'Asia/Seoul',3,'병동팀') ON CONFLICT DO NOTHING;""")
 statements.append('COMMIT;')
 try: sql('\n'.join(statements))
 except subprocess.CalledProcessError as error: raise RuntimeError(error.stderr) from None
 print('가상 돌봄 작성권한·담당 배정 6건 / 평가·인계·주의 14건 / 돌봄 업무 42건 / 음성 계획 6건 준비')
if __name__=='__main__':main()
