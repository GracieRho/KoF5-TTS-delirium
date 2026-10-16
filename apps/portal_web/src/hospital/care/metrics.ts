import type { CareData, CareNote } from './api'
import type { Patient } from '../../shared/types/domain'
export function patientCare(data:CareData,patient:Patient) {
 const owns=(row:{patient_id:string;encounter_id:string})=>row.patient_id===patient.patient_id&&row.encounter_id===patient.encounter_id
 const notes=data.notes.filter(owns).sort((a,b)=>Date.parse(b.observed_at)-Date.parse(a.observed_at))
 const tasks=data.tasks.filter(owns), plans=data.plans.filter(owns)
 const resolved=new Set(notes.filter(n=>n.kind==='resolution').map(n=>n.related_note_id))
 return {accessible:data.permissions.some(p=>owns(p)&&p.can_read),notes,tasks,plans,activities:data.activities.filter(owns).sort((a,b)=>Date.parse(b.recorded_at)-Date.parse(a.recorded_at)),
  assessment:notes.find(n=>n.kind==='assessment'),
  concerns:notes.filter(n=>n.kind==='concern'&&!resolved.has(n.note_id)),
  open:tasks.filter(t=>t.status==='open'), held:tasks.filter(t=>t.status==='held'),
  pendingPlans:plans.filter(p=>p.status==='planned').sort((a,b)=>Date.parse(a.scheduled_at)-Date.parse(b.scheduled_at))}
}
export function assessmentLabel(note:CareNote|undefined) {
 if(!note)return '평가 기록 없음'
 return `${note.tool} · ${note.result==='unable'?'평가 불가':note.result==='positive'?'양성 결과':'음성 결과'}${note.score===null?'':` ${note.score}점`}`
}
export function isOverdue(date:string,now=Date.now()) {return Date.parse(date)<now}
export function localInput(date=new Date()) {return new Date(date.getTime()-date.getTimezoneOffset()*60000).toISOString().slice(0,16)}
