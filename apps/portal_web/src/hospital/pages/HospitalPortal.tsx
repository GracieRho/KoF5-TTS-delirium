import { SYNTHETIC_PATIENT_ID } from '../../shared/types/constants'
import { Disclosure } from '../../shared/components/Disclosure'
import { MessageApproval } from '../components/MessageApproval'
import { ContextApproval } from '../components/ContextApproval'
import { DevicePairing } from '../components/DevicePairing'
import { AlertDashboard } from '../components/AlertDashboard'
import { TranscriptList } from '../components/TranscriptList'
import { StaffVoiceTrial } from '../components/StaffVoiceTrial'
import { useEffect, useState } from 'react'
import '../styles/hospital.css'
import hospitalSymbol from '../assets/favilium-symbol.svg'
import hospitalIcon from '../assets/favilium-icon.svg'
import { useAuth } from '../../shared/auth/AuthContext'
import { WorkspaceShell } from '../../shared/components/WorkspaceShell'
import { Icon } from '../../shared/components/Icon'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { PatientRegistration } from '../components/PatientRegistration'
import { QueueList } from '../components/QueueList'
import { useHospitalPortal } from '../hooks/useHospitalPortal'
import { CareDashboard } from '../care/CareDashboard'
import { PatientCareWorkspace } from '../care/PatientCareWorkspace'
import { useHospitalCare } from '../care/useHospitalCare'
import { patientCare } from '../care/metrics'
import { formatHospitalTime } from '../utils/format'
import { PURPOSE_LABELS } from '../care/api'
type View='dashboard'|'patients'|'voice'|'handoff'
const NAV:Record<View,string>={dashboard:'돌봄 현황',patients:'담당 환자',voice:'음성·전달 일정',handoff:'인계·주의 사항'}
export function HospitalPortal() {
 const auth=useAuth(),portal=useHospitalPortal(),care=useHospitalCare()
 const [view,setView]=useState<View>('dashboard'),[detail,setDetail]=useState(false),[registration,setRegistration]=useState(false)
 useEffect(()=>{const icon=document.querySelector<HTMLLinkElement>('link[rel="icon"]'),oldIcon=icon?.getAttribute('href'),oldTitle=document.title
  icon?.setAttribute('href',hospitalIcon);document.title='Favilium · 병원'
  return()=>{if(oldIcon)icon?.setAttribute('href',oldIcon);document.title=oldTitle}
 },[])
 function select(id:string) {setView('patients');setDetail(true);void portal.select(id)}
 const concerns=portal.patients.flatMap(patient=>patientCare(care.data,patient).concerns.map(note=>({patient,note})))
 const readable=portal.patients.filter(p=>patientCare(care.data,p).accessible).length
 const scopeNote=<p className="form-hint">돌봄 열람이 확인된 {readable}명의 기록 기준입니다.{portal.patients.length>readable&&` 나머지 ${portal.patients.length-readable}명은 기록 미확인입니다.`}</p>
 const plans=care.data.plans.filter(plan=>plan.status==='planned').sort((a,b)=>Date.parse(a.scheduled_at)-Date.parse(b.scheduled_at))
 return <WorkspaceShell brandSymbol={hospitalSymbol} area="병원" title="병동 돌봄" subtitle="변화를 살피고 돌봄을 연결해요" homeHref="/hospital" current={detail&&portal.selected?portal.selected.staff_display_name:NAV[view]} status="병동팀" navigation={<>
 {(Object.keys(NAV) as View[]).map(key=><button key={key} aria-current={view===key?'page':undefined} onClick={()=>{setView(key);setDetail(false)}}><Icon name={key==='dashboard'?'home':key==='patients'?'patient':key==='voice'?'voice':'memory'}/>{NAV[key]}{key==='handoff'&&concerns.length>0&&<span className="nav-count">{concerns.length}</span>}</button>)}
 <button onClick={()=>setRegistration(true)}><Icon name="plus"/>환자 등록</button><button onClick={auth.signOut}>로그아웃</button>
 </>}>
 {care.error?<div className="care-blocking" role="alert"><h1>돌봄 기록을 확인하지 못했습니다</h1><p>{care.error}</p><button onClick={()=>void care.refresh()}>다시 연결</button></div>:care.loading&&!care.data.tasks.length?<p role="status">병동 돌봄 기록을 불러오고 있습니다…</p>:<>
 {(view==='dashboard'||view==='patients')&&(!detail||!portal.selected)&&<CareDashboard title={view==='dashboard'?'병동 돌봄 현황':'담당 환자'} patients={portal.patients} data={care.data} onSelect={select} onRegister={()=>setRegistration(true)}/>}
 {view==='patients'&&detail&&portal.selected&&<PatientCareWorkspace key={portal.selected.patient_id} patient={portal.selected} care={care} facts={portal.facts} messages={portal.messages} onBack={()=>setDetail(false)}/>}
 {view==='patients'&&detail&&portal.selected?.patient_id===SYNTHETIC_PATIENT_ID&&portal.api&&portal.token&&<section className="stack" aria-label="승인·기기 업무">
 <Disclosure title="병원 메시지 승인"><MessageApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/></Disclosure>
 <Disclosure title="병원 맥락 승인"><ContextApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/></Disclosure>
 <Disclosure title="대화 전사"><TranscriptList api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure>
 <Disclosure title="위험 발화 보조 경고"><AlertDashboard api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure>
 <Disclosure title="iPad 연결"><DevicePairing api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure>
 <Disclosure title="직원 음성 확인"><StaffVoiceTrial api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure>
 </section>}
 {view==='voice'&&<section><header className="care-page-heading"><div><h1>음성·전달 일정</h1><p>음성 사용 계획과 병원 승인 안내를 구분해 확인합니다.</p></div></header>{scopeNote}<h2>가족 음성 사용 계획 <span className="compact">{plans.length}건</span></h2><ul className="care-global-list">{plans.map(plan=>{const patient=portal.patients.find(p=>p.patient_id===plan.patient_id);return <li key={plan.schedule_id}><div><strong>{patient?.staff_display_name||'환자 확인 필요'}</strong><small>{patient?.ward_ref} {patient?.room_ref}</small></div><div><strong>{PURPOSE_LABELS[plan.purpose]}</strong><p>{plan.script}</p><small>{formatHospitalTime(plan.scheduled_at)} · {plan.duration_minutes}분 · {plan.owner_label}</small></div><div><span className="care-label">계획 저장됨</span><small>기기 재생 연결 확인 전</small><button onClick={()=>select(plan.patient_id)}>환자에서 관리</button></div></li>})}</ul>{!plans.length&&<p className="empty-state">{readable?'열람 범위에 등록된 음성 사용 계획이 없습니다.':'돌봄 열람 권한 확인이 필요합니다.'}</p>}<h2 className="care-history-title">병원 승인 안내 · 전달 대기 {portal.queue.length}건</h2><QueueList messages={portal.queue} patients={portal.patients}/></section>}
 {view==='handoff'&&<section><header className="care-page-heading"><div><h1>인계·주의 사항</h1><p>담당자가 확인할 기록과 다음 근무 인계를 모아봅니다.</p></div></header>{scopeNote}<h2>확인할 주의 기록 {concerns.length}건</h2><ul className="care-global-list">{concerns.map(({patient,note})=><li key={note.note_id}><div><strong>{patient.staff_display_name}</strong><small>{patient.ward_ref} {patient.room_ref}</small></div><div><p>{note.summary}</p><small>{formatHospitalTime(note.observed_at)} · {note.severity==='urgent'?'즉시 확인 필요':'담당자 확인 필요'}</small></div><button onClick={()=>select(patient.patient_id)}>환자 기록 열기</button></li>)}</ul>{!concerns.length&&<p className="empty-state">{readable?'열람 범위에 등록된 미확인 주의 기록이 없습니다.':'돌봄 열람 권한 확인이 필요합니다.'}</p>}<h2 className="care-history-title">최근 인계</h2><ul className="care-global-list">{care.data.notes.filter(n=>n.kind==='handoff').sort((a,b)=>Date.parse(b.observed_at)-Date.parse(a.observed_at)).map(note=><li key={note.note_id}><div><strong>{portal.patients.find(p=>p.patient_id===note.patient_id)?.staff_display_name||'환자 확인 필요'}</strong><small>{note.recipient}</small></div><div><p>{note.summary}</p><small>{formatHospitalTime(note.observed_at)} · 확인 회신은 별도 기록</small></div><button onClick={()=>select(note.patient_id)}>환자 기록 열기</button></li>)}</ul></section>}
 </>}
 <ResponsiveSheet open={registration} title="환자 등록" onClose={()=>setRegistration(false)}>{portal.api&&portal.token&&<PatientRegistration api={portal.api} token={portal.token} readiness={portal.readiness} onDone={async()=>{await portal.refresh();await care.refresh();setRegistration(false)}}/>}</ResponsiveSheet>
 <StatusMessage>{care.notice}</StatusMessage><StatusMessage>{portal.status}</StatusMessage>
 </WorkspaceShell>
}
