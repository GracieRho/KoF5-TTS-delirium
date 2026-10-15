import { useEffect, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { materialApi, MATERIAL_LABELS, VOICE_LABELS, type FamilyMaterial } from '../../shared/api/familyMaterials'
import { HelpTooltip } from '../../shared/components/HelpTooltip'
import { Select } from '../../shared/components/Select'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import type { Patient } from '../../shared/types/domain'
import type { VoicePlan } from '../care/api'
import { formatHospitalTime } from '../utils/format'

export function FamilyMaterialReview({patient,plans,writable}:{patient:Patient;plans:VoicePlan[];writable:boolean}) {
 const {api,token}=useAuth()
 const [materials,setMaterials]=useState<FamilyMaterial[]>([]),[bindings,setBindings]=useState<{schedule_id:string;material_id:string}[]>([])
 const [loading,setLoading]=useState(true),[error,setError]=useState(''),[busy,setBusy]=useState(false)
 const [review,setReview]=useState<FamilyMaterial|null>(null),[note,setNote]=useState(''),[decision,setDecision]=useState<'approved'|'rejected'>('approved'),[schedule,setSchedule]=useState('')
 async function reload(){if(!api||!token)return;setLoading(true);setError('');try{const [m,b]=await Promise.all([materialApi.list(api,token,patient.patient_id,patient.encounter_id||''),materialApi.bindings(api,token)]);setMaterials(m);setBindings(b)}catch{setError('가족 자료를 확인하지 못했습니다.')}finally{setLoading(false)}}
 useEffect(()=>{void reload()},[api,token,patient.patient_id,patient.encounter_id])
 async function mutate(action:()=>Promise<unknown>){setBusy(true);setError('');try{await action();await reload();setReview(null)}catch{setError('처리 결과를 확인하지 못했습니다. 다시 조회한 뒤 상태를 확인해주세요.')}finally{setBusy(false)}}
 const available=plans.filter(p=>p.status==='planned')
 return <section className="stack" aria-label="보호자가 보낸 가족 자료"><div className="section-heading"><div className="heading-with-help"><h2>가족 자료 검토</h2><HelpTooltip label="가족 자료 검토 도움말">보호자가 보낸 시점의 소개·기억과 음성 등록 상태입니다. 검토 완료는 재생 승인이 아닙니다. 변경된 자료는 새 버전으로 다시 검토합니다.</HelpTooltip></div><button disabled={busy||loading} onClick={()=>void reload()}>다시 조회</button></div>
 {error?<p role="alert" className="blocking-note">{error}</p>:loading?<p role="status">가족 자료 확인 중…</p>:!materials.length?<p className="empty-state">보호자가 보낸 가족 자료가 없습니다.</p>:<ul className="care-records">{materials.map(m=><li key={m.material_id}><div className="care-record-heading"><strong>{m.profile.guardian_name} · {m.profile.relationship} · 버전 {m.revision}</strong><span className="care-label">{MATERIAL_LABELS[m.status]}</span></div><small>{formatHospitalTime(m.submitted_at)}</small><p>보호자 제출 음성 상태 · {VOICE_LABELS[m.voice_status]} · 등록 여부 미검증 <HelpTooltip label="음성 상태 도움말">보호자가 제출한 값입니다. 공급자 등록 여부와 현재 사용 가능 여부를 병원에서 검증한 상태가 아닙니다. 환자 재생에는 별도 연결이 필요합니다.</HelpTooltip></p>
 <details><summary>소개와 기억 {m.memories.length}개</summary><p>{m.profile.patient_alias} · {m.profile.address_as}</p>{m.memories.map(memory=><div key={memory.id}><strong>{memory.category==='avoid'?'피할 주제 · ':''}{memory.title}</strong><p>{memory.content}</p></div>)}<small>자료 ID {m.material_id} · 버전 {m.revision}</small></details>{m.review_note&&<p>검토 의견 · {m.review_note}</p>}
 {m.status==='pending'&&<button disabled={!writable||busy} onClick={()=>{setReview(m);setNote('');setDecision('approved')}}>자료 검토</button>}
 {m.status==='approved'&&<div className="form-stack"><Select label={`버전 ${m.revision}에 연결할 음성 계획`} value={schedule} onValueChange={setSchedule}><option value="">계획 선택</option>{available.map(p=><option key={p.schedule_id} value={p.schedule_id}>{formatHospitalTime(p.scheduled_at)} · {p.script}</option>)}</Select><button disabled={!writable||busy||!schedule} onClick={()=>api&&token&&void mutate(()=>materialApi.link(api,token,m.material_id,schedule))}>선택한 계획에 연결</button></div>}
 {bindings.filter(b=>b.material_id===m.material_id).map(b=><p key={b.schedule_id}>연결된 계획 · {plans.find(p=>p.schedule_id===b.schedule_id)?.script||b.schedule_id} · {m.status==='approved'?'검토 자료 연결됨':'자료 재검토 필요'}</p>)}
 </li>)}</ul>}
 <ResponsiveSheet open={Boolean(review)} title="가족 자료 검토" onClose={()=>{if(!busy)setReview(null)}}><form className="form-stack" onSubmit={e=>{e.preventDefault();if(api&&token&&review)void mutate(()=>materialApi.review(api,token,review.material_id,decision,note))}}><Select label="검토 결과" value={decision} onValueChange={v=>setDecision(v as 'approved'|'rejected')}><option value="approved">검토 완료</option><option value="rejected">보완 요청</option></Select><label>검토 의견<textarea required maxLength={500} value={note} onChange={e=>setNote(e.target.value)}/></label><button className="primary" disabled={busy||!note.trim()}>검토 기록 저장</button></form></ResponsiveSheet>
 </section>
}
