import { useEffect, useState } from 'react'
import type { Patient, HospitalFact, HospitalMessage } from '../../shared/types/domain'
import { useAuth } from '../../shared/auth/AuthContext'
import { Panel } from '../../shared/components/Panel'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import { PatientSummary } from '../components/PatientSummary'
import { formatHospitalTime } from '../utils/format'
import { CareNoteForm, CareTaskForm, ReasonForm, VoicePlanForm } from './CareForms'
import { KIND_LABELS, PURPOSE_LABELS, RESULT_LABELS, TASK_LABELS, careApi, type CareNote, type CareTask, type NoteKind, type VoicePlan } from './api'
import { assessmentLabel, isOverdue, patientCare } from './metrics'
import type { useHospitalCare } from './useHospitalCare'

type Tab='overview'|'observations'|'plan'|'voice'|'handoff'
const TABS:Record<Tab,string>={overview:'환자 개요',observations:'평가·관찰',plan:'돌봄 계획',voice:'가족 음성',handoff:'인계·이력'}
type Editor={type:'note';kind:NoteKind;related?:string}|{type:'task'}|{type:'voice'}|{type:'task-state';task:CareTask;status:'completed'|'held'|'open'}|{type:'cancel';plan:VoicePlan}
type Props={patient:Patient;care:ReturnType<typeof useHospitalCare>;facts:HospitalFact[];messages:HospitalMessage[];onBack:()=>void}
export function PatientCareWorkspace({patient,care,facts,messages,onBack}:Props) {
 const {api,token}=useAuth(), rows=patientCare(care.data,patient)
 const [tab,setTab]=useState<Tab>('overview'),[editor,setEditor]=useState<Editor|null>(null)
 const [readiness,setReadiness]=useState<Awaited<ReturnType<typeof careApi.readiness>>|null>(null),[readyError,setReadyError]=useState(false)
 useEffect(()=>{let active=true;setReadiness(null);setReadyError(false)
  if(api&&token&&patient.encounter_id) void careApi.readiness(api,token,patient.patient_id,patient.encounter_id).then(row=>{if(active)setReadiness(row)}).catch(()=>{if(active)setReadyError(true)})
  return()=>{active=false}
 },[api,token,patient.patient_id,patient.encounter_id])
 const writable=Boolean(readiness?.authorized&&readiness.encounter_active)&&!care.error
 const openNote=(kind:NoteKind,related?:string)=>setEditor({type:'note',kind,related})
 const close=()=>{if(!care.busy)setEditor(null)}
 async function create(table:'care_note'|'care_task'|'care_voice_schedule',body:Record<string,unknown>) {if(await care.save(table,body))setEditor(null)}
 const concerns=rows.concerns
 const title=editor?.type==='note'?KIND_LABELS[editor.kind]+' 기록':editor?.type==='task'?'돌봄 업무 추가':editor?.type==='voice'?'가족 음성 계획':editor?.type==='cancel'?'음성 계획 취소':'돌봄 수행 기록'
 function noteList(notes:CareNote[]) {return notes.length?<ol className="care-records">{notes.map(note=><li key={note.note_id}>
   <div className="care-record-heading"><strong>{KIND_LABELS[note.kind]}{note.tool?` · ${note.tool}`:''}</strong><time>{formatHospitalTime(note.observed_at)}</time></div>
   {note.kind==='assessment'&&<span className={`care-label ${note.result==='positive'?'attention':''}`}>{RESULT_LABELS[note.result]}{note.score===null?'':` · ${note.score}점`}</span>}
   {note.kind==='concern'&&<span className="care-label attention">{note.severity==='urgent'?'즉시 확인 필요':'담당자 확인 필요'}</span>}
   <p>{note.summary}</p>{rows.notes.filter(n=>n.kind==='correction'&&n.related_note_id===note.note_id).map(n=><p className="care-correction" key={n.note_id}><strong>정정·보충</strong> {n.summary} <small>{formatHospitalTime(n.created_at)}</small></p>)}{note.recipient&&<small>인계 대상 · {note.recipient} · 확인 회신은 별도 기록</small>}
   <div className="care-record-footer"><small>입력 {formatHospitalTime(note.created_at)}</small>{writable&&<button disabled={care.busy} onClick={()=>openNote('correction',note.note_id)}>정정 남기기</button>}{note.kind==='concern'&&concerns.some(n=>n.note_id===note.note_id)&&<button disabled={!writable||care.busy} onClick={()=>openNote('resolution',note.note_id)}>확인·처리 기록</button>}</div>
  </li>)}</ol>:<p className="empty-state">아직 기록이 없습니다. 관찰한 내용을 남겨주세요.</p>}
 function tasks() {return rows.tasks.length?<ul className="care-task-list">{[...rows.tasks].sort((a,b)=>Date.parse(a.due_at)-Date.parse(b.due_at)).map(task=><li key={task.task_id}>
  <div><span className="care-category">{TASK_LABELS[task.category]}</span><h3>{task.title}</h3><p>{task.owner_label} · {formatHospitalTime(task.due_at)}</p>{task.outcome&&<p className="compact">{task.outcome}</p>}</div>
  <div className="care-task-actions"><span className={`care-label ${task.status==='held'||(task.status==='open'&&isOverdue(task.due_at))?'attention':''}`}>{task.status==='completed'?'수행 기록됨':task.status==='held'?'보류':isOverdue(task.due_at)?'기한 지남':'예정'}</span>
   {task.status==='open'?<><button disabled={!writable||care.busy} onClick={()=>setEditor({type:'task-state',task,status:'completed'})}>수행 기록</button><button disabled={!writable||care.busy} onClick={()=>setEditor({type:'task-state',task,status:'held'})}>보류</button></>:<button disabled={!writable||care.busy} onClick={()=>setEditor({type:'task-state',task,status:'open'})}>다시 열기</button>}</div>
 </li>)}</ul>:<p className="empty-state">돌봄 계획을 추가해 담당자와 확인 기한을 정해주세요.</p>}
 function plans() {return rows.plans.length?<ul className="care-task-list">{[...rows.plans].sort((a,b)=>Date.parse(a.scheduled_at)-Date.parse(b.scheduled_at)).map(plan=><li key={plan.schedule_id}><div><span className="care-category">{PURPOSE_LABELS[plan.purpose]}</span><h3>{formatHospitalTime(plan.scheduled_at)} · {plan.duration_minutes}분</h3><p>{plan.script}</p><p className="compact">확인 담당 · {plan.owner_label}</p>{plan.cancel_reason&&<p>취소 사유 · {plan.cancel_reason}</p>}</div><div className="care-task-actions"><span className="care-label">{plan.status==='cancelled'?'취소됨':'계획 저장됨'}</span>{plan.status==='planned'&&<button disabled={!writable||care.busy} onClick={()=>setEditor({type:'cancel',plan})}>계획 취소</button>}</div></li>)}</ul>:<p className="empty-state">저장된 음성 사용 계획이 없습니다.</p>}
 return <section className="care-detail">
 <button className="care-back" onClick={onBack}>← 환자 목록</button>
 <header className="care-patient-heading"><div><h1>{patient.staff_display_name}</h1><p>{patient.ward_ref||'병동 미등록'} · {patient.room_ref||'병실 미등록'} {patient.bed_ref||''}<span>환자 번호 {patient.ehr_patient_ref}</span></p></div><button className="primary" disabled={!writable} onClick={()=>openNote('assessment')}>평가 기록 추가</button></header>
 {!patient.encounter_id&&<p className="blocking-note">현재 입원이 등록되지 않았습니다. 입원 정보를 연결한 뒤 돌봄을 기록할 수 있습니다.</p>}
 {readyError&&<p className="blocking-note">돌봄 작성 권한·현재 입원을 확인하지 못했습니다. 담당 배정과 연결 상태를 확인해주세요.</p>}
 <div className="tabs care-tabs" role="tablist" aria-label="환자 돌봄 업무">{(Object.keys(TABS) as Tab[]).map((key,index,keys)=><button key={key} id={`care-tab-${key}`} role="tab" aria-selected={tab===key} aria-controls={`care-panel-${key}`} tabIndex={tab===key?0:-1} onClick={()=>setTab(key)} onKeyDown={e=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const next=e.key==='Home'?keys[0]:e.key==='End'?keys[keys.length-1]:keys[(index+(e.key==='ArrowRight'?1:-1)+keys.length)%keys.length];setTab(next);document.getElementById(`care-tab-${next}`)?.focus()}}}>{TABS[key]}{rows.accessible&&key==='plan'&&<span>{rows.open.length}</span>}{key==='handoff'&&concerns.length>0&&<span>{concerns.length}</span>}</button>)}</div>
 {!rows.accessible&&<p className="blocking-note">돌봄 기록 열람 권한을 확인할 수 없습니다. 아래 병원 승인 안내만 확인할 수 있으며, 임상 기록이 없다는 의미가 아닙니다.</p>}
 <div role="tabpanel" id={`care-panel-${tab}`} aria-labelledby={`care-tab-${tab}`} tabIndex={0}>
 {tab==='overview'&&<>{rows.accessible&&<><div className="care-detail-stats"><div><span>최근 평가 기록</span><strong>{assessmentLabel(rows.assessment)}</strong><small>{rows.assessment?formatHospitalTime(rows.assessment.observed_at):'미평가와 정상 결과를 구분합니다'}</small></div><div><span>확인할 돌봄</span><strong>{rows.open.length}건 <small>보류 {rows.held.length}</small></strong></div><div><span>미확인 주의 기록</span><strong>{concerns.length}건</strong></div></div>
 <div className="care-overview-grid"><Panel title="지금 확인할 돌봄" actions={<button onClick={()=>setTab('plan')}>전체 보기</button>}>{rows.open.slice(0,3).map(task=><div className="care-next-row" key={task.task_id}><div><strong>{task.title}</strong><small>{task.owner_label} · {formatHospitalTime(task.due_at)}</small></div><span className={`care-label ${isOverdue(task.due_at)?'attention':''}`}>{isOverdue(task.due_at)?'기한 지남':'예정'}</span></div>)}{!rows.open.length&&<p className="empty-state">확인할 업무가 없습니다.</p>}</Panel><Panel title="가족 목소리 준비" actions={<button onClick={()=>setTab('voice')}>계획 관리</button>}><div className="care-readiness-row"><span>가족 연결</span><strong>{readiness?.family_linked?'연결 확인됨':'연결 확인 필요'}</strong></div><div className="care-readiness-row"><span>기기 재생</span><strong>연결 확인 전</strong></div><p className="compact">음성 계획 {rows.pendingPlans.length}건 · 실제 재생 기록과 구분됩니다.</p></Panel></div>
 {concerns.length>0&&<Panel title="담당자 확인이 필요한 기록" actions={<button onClick={()=>setTab('handoff')}>확인하기</button>}>{concerns.map(n=><p key={n.note_id}>{n.summary}</p>)}</Panel>}
 </>}<Panel title="병원에서 확인한 안내"><PatientSummary facts={facts} messages={messages}/></Panel></>}
 {tab==='observations'&&<>{!rows.accessible?<p className="empty-state">돌봄 열람 권한 확인이 필요합니다.</p>:<><div className="section-heading"><h2>평가와 변화 관찰</h2><div className="button-row"><button disabled={!writable} onClick={()=>openNote('observation')}>관찰 남기기</button><button className="primary" disabled={!writable} onClick={()=>openNote('assessment')}>평가 기록</button></div></div><p className="form-hint">직원이 실시한 평가 결과와 변화를 기록합니다. 평가 결과는 최종 임상 진단과 구분됩니다.</p>{noteList(rows.notes.filter(n=>['assessment','observation','correction'].includes(n.kind)))}</>}</>}
 {tab==='plan'&&<>{!rows.accessible?<p className="empty-state">돌봄 열람 권한 확인이 필요합니다.</p>:<><div className="section-heading"><h2>개인별 비약물 돌봄</h2><button className="primary" disabled={!writable} onClick={()=>setEditor({type:'task'})}>돌봄 업무 추가</button></div><p className="form-hint">개별 상태와 기관 지침에 맞춰 담당자가 확인합니다. 보류할 때는 사유를 기록해주세요.</p>{tasks()}</>}</>}
 {tab==='voice'&&<>{!rows.accessible?<p className="empty-state">돌봄 열람 권한 확인이 필요합니다.</p>:<><div className="section-heading"><h2>가족 목소리와 사용 계획</h2><button className="primary" disabled={!writable} onClick={()=>setEditor({type:'voice'})}>음성 계획 추가</button></div><div className="care-readiness"><strong>{readiness?.family_linked?'가족 연결 확인됨':'가족 연결 확인 필요'}</strong><p>{readiness?.reason||'담당 배정과 현재 입원을 확인하고 있습니다.'}</p><small>계획 등록은 재생 승인이 아닙니다. 환자 의사·동의·피해야 할 주제·수면 시간을 확인하세요.</small></div>{plans()}</>}</>}
 {tab==='handoff'&&<>{!rows.accessible?<p className="empty-state">돌봄 열람 권한 확인이 필요합니다.</p>:<><div className="section-heading"><h2>주의 사항과 다음 근무 인계</h2><div className="button-row"><button disabled={!writable} onClick={()=>openNote('concern')}>주의 사항 기록</button><button className="primary" disabled={!writable} onClick={()=>openNote('handoff')}>인계 남기기</button></div></div>{noteList(rows.notes.filter(n=>['handoff','concern','resolution'].includes(n.kind)))}<h2 className="care-history-title">변경 이력</h2><ol className="care-activity">{rows.activities.map(a=><li key={a.activity_id}><time>{formatHospitalTime(a.recorded_at)}</time><p>{a.detail}</p></li>)}</ol></>}</>}
 </div>
 <ResponsiveSheet open={Boolean(editor)} title={title} onClose={close}>
 {editor?.type==='note'&&<CareNoteForm key={`${editor.kind}-${editor.related||''}`} patient={patient} busy={care.busy} kind={editor.kind} related={editor.related} save={body=>create('care_note',body)}/>}
 {editor?.type==='task'&&<CareTaskForm patient={patient} busy={care.busy} save={body=>create('care_task',body)}/>}
 {editor?.type==='voice'&&<VoicePlanForm patient={patient} busy={care.busy} save={body=>create('care_voice_schedule',body)}/>}
 {editor?.type==='task-state'&&<ReasonForm label={editor.status==='held'?'보류 사유':editor.status==='open'?'다시 확인할 내용':'수행한 내용'} busy={care.busy} save={async reason=>{if(await care.save('care_task',{status:editor.status,outcome:reason},editor.task.task_id,editor.task.version))setEditor(null)}}/>}
 {editor?.type==='cancel'&&<ReasonForm label="계획 취소 사유" busy={care.busy} save={async reason=>{if(await care.save('care_voice_schedule',{status:'cancelled',cancel_reason:reason},editor.plan.schedule_id,editor.plan.version))setEditor(null)}}/>}
 </ResponsiveSheet>
 </section>
}
