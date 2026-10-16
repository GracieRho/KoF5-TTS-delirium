import type { SupabaseRest } from '../../shared/api/supabase'
export type NoteKind = 'assessment' | 'observation' | 'handoff' | 'concern' | 'resolution' | 'correction'
export type CareNote = { note_id:string;patient_id:string;encounter_id:string;kind:NoteKind;summary:string;tool:'4AT'|'CAM-ICU'|'ICDSC'|null;care_setting:'ward'|'icu';result:'not_applicable'|'negative'|'positive'|'unable';score:number|null;severity:'routine'|'attention'|'urgent';recipient:string|null;related_note_id:string|null;observed_at:string;created_at:string;created_by:string }
export type CareTask = {task_id:string;patient_id:string;encounter_id:string;category:string;title:string;owner_label:string;due_at:string;status:'open'|'completed'|'held';outcome:string;version:number;completed_at:string|null}
export type VoicePlan = {schedule_id:string;patient_id:string;encounter_id:string;purpose:string;script:string;scheduled_at:string;duration_minutes:number;owner_label:string;status:'planned'|'cancelled';cancel_reason:string|null;version:number}
export type Activity = {activity_id:string;patient_id:string;encounter_id:string;entity:string;action:string;detail:string;recorded_at:string;actor_id:string}
export type CareData = {permissions:{patient_id:string;encounter_id:string;can_read:boolean;can_document:boolean}[];notes:CareNote[];tasks:CareTask[];plans:VoicePlan[];activities:Activity[]}
export const EMPTY_CARE:CareData = {permissions:[],notes:[],tasks:[],plans:[],activities:[]}
export const TASK_LABELS:Record<string,string> = {orientation:'지남력 안내',family:'가족 참여',sensory:'안경·보청기',sleep:'수면 환경',nutrition:'수분·영양 확인',mobility:'활동 지원',clinical_review:'의료진 검토 요청'}
export const PURPOSE_LABELS:Record<string,string> = {orientation:'날짜·장소 안내',reassurance:'익숙한 목소리로 안심',family_story:'가족 이야기'}
export const KIND_LABELS:Record<NoteKind,string> = {assessment:'평가',observation:'관찰',handoff:'인계',concern:'주의 사항',resolution:'확인·처리 기록',correction:'정정'}
export const RESULT_LABELS:Record<string,string> = {positive:'양성 결과 기록',negative:'음성 결과 기록',unable:'평가 불가',not_applicable:'평가 기록 없음'}
export const careApi = {
 async load(api:SupabaseRest,token:string):Promise<CareData> {
  const rows = await Promise.all(['care_note','care_task','care_voice_schedule','care_activity','care_patient_access'].map(table => api.request<unknown[]>(`/rest/v1/${table}?select=*&limit=1000`,{token,schema:'api'})))
  // shortcut: bounded ward workspace; add server pagination before exceeding 1,000 records per table.
  if (rows.some(row => row.length >= 1000)) throw new Error('기록 표시 한도를 초과했습니다. 범위를 나누어 조회해야 합니다.')
  return {notes:rows[0] as CareNote[],tasks:rows[1] as CareTask[],plans:rows[2] as VoicePlan[],activities:rows[3] as Activity[],permissions:rows[4] as CareData['permissions']}
 },
 async write(api:SupabaseRest,token:string,table:'care_note'|'care_task'|'care_voice_schedule',body:unknown,id?:string,version?:number) {
  const key = table === 'care_note' ? 'note_id' : table === 'care_task' ? 'task_id' : 'schedule_id'
  const filter = id ? `?${key}=eq.${encodeURIComponent(id)}&version=eq.${version}` : ''
  const rows = await api.request<unknown[]>(`/rest/v1/${table}${filter}`,{method:id?'PATCH':'POST',token,schema:'api',body,returnRow:true})
  if (rows.length!==1) throw new Error('다른 직원이 변경했거나 접근 상태가 바뀌었습니다. 최신 기록을 확인해주세요.')
 },
 readiness:(api:SupabaseRest,token:string,patient:string,encounter:string) => api.request<{authorized:boolean;family_linked:boolean;playback_ready:boolean;reason:string;encounter_active:boolean}>('/rest/v1/rpc/care_voice_readiness',{method:'POST',token,schema:'api',body:{_patient:patient,_encounter:encounter}})
}
