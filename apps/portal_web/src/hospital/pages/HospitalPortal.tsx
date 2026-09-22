import { useEffect, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { usePortalConnection } from '../../shared/hooks/usePortalConnection'
import { SYNTHETIC_PATIENT_ID } from '../../shared/types/constants'
import { AppHeader } from '../../shared/components/AppHeader'
import { Disclosure } from '../../shared/components/Disclosure'
import { LoginForm } from '../../shared/components/LoginForm'
import { Panel } from '../../shared/components/Panel'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { AlertDashboard } from '../components/AlertDashboard'
import { ContextApproval } from '../components/ContextApproval'
import { DevicePairing } from '../components/DevicePairing'
import { HospitalTabs, type HospitalTab } from '../components/HospitalTabs'
import { MessageApproval } from '../components/MessageApproval'
import { PatientList } from '../components/PatientList'
import { PatientRegistration } from '../components/PatientRegistration'
import { PatientSummary } from '../components/PatientSummary'
import { QueueList } from '../components/QueueList'
import { StaffVoiceTrial } from '../components/StaffVoiceTrial'
import { TranscriptList } from '../components/TranscriptList'
import { useHospitalPortal } from '../hooks/useHospitalPortal'

export function HospitalPortal() {
  const auth = useAuth(); const connection = usePortalConnection(); const portal = useHospitalPortal(); const [tab, setTab] = useState<HospitalTab>('summary'); const synthetic = portal.selected?.patient_id === SYNTHETIC_PATIENT_ID
  useEffect(() => { if (!synthetic && ['messages','context','safety','device'].includes(tab)) setTab('summary') }, [synthetic, tab])
  return <><AppHeader area="병원"/><main className="page"><div className="eyebrow">병원 업무</div><h1>담당 환자의 확인된 정보만<br/>한곳에서 봅니다.</h1><p className="page-intro">기관 자격과 담당 환자 배정을 확인한 직원만 현재 입원과 승인된 병원 정보를 조회합니다.</p>
    {!auth.token ? <div className="portal-grid"><Panel title="병원 직원 로그인" description="기관에서 자격을 검증한 계정으로 로그인하세요."><LoginForm kind="병원 직원" ready={connection.ready} onLogin={auth.signIn}/></Panel><Panel className="boundary" title="병원에서 승인한 내용"><p>가족 기억은 보호자 화면에서 관리합니다. 병실·검사·예약 메시지는 현재 입원과 직원 승인 상태를 따로 확인합니다.</p><p className="compact">실제 환자 사용은 기관 승인, 동의, 환자 거부 및 개인정보 처리 절차가 완료된 뒤에만 시작합니다.</p></Panel></div> :
    <div className="hospital-grid"><aside className="stack hospital-sidebar"><Panel title="담당 환자" description="현재 권한으로 조회할 수 있는 환자입니다." actions={<button onClick={auth.signOut}>로그아웃</button>}><PatientList patients={portal.patients} selectedId={portal.selected?.patient_id} onSelect={id => { void portal.select(id); setTab('summary') }}/><StatusMessage>{portal.status}</StatusMessage></Panel></aside><section className="panel"><HospitalTabs value={tab} onChange={setTab} synthetic={synthetic}/><div role="tabpanel" id={`hospital-panel-${tab}`} aria-labelledby={`hospital-tab-${tab}`} tabIndex={0}>
      {tab === 'summary' && (portal.selected ? <PatientSummary patient={portal.selected} facts={portal.facts} messages={portal.messages}/> : <p className="empty-state">왼쪽에서 담당 환자를 선택하세요.</p>)}
      {tab === 'queue' && <QueueList messages={portal.queue}/>} 
      {tab === 'registration' && portal.api && portal.token && <PatientRegistration api={portal.api} token={portal.token} readiness={portal.readiness} onDone={portal.refresh}/>} 
      {synthetic && portal.selected && portal.api && portal.token && tab === 'messages' && <MessageApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/>} 
      {synthetic && portal.selected && portal.api && portal.token && tab === 'context' && <ContextApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/>} 
      {synthetic && portal.selected && portal.api && portal.token && tab === 'safety' && <div className="stack"><Disclosure title="오늘의 합성 대화 전사" open><TranscriptList api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure><Disclosure title="합성 위험 발화 보조 경고"><AlertDashboard api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure></div>}
      {synthetic && portal.selected && portal.api && portal.token && tab === 'device' && <div className="stack"><Disclosure title="합성 iPad 연결 시험" open><DevicePairing api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure><Disclosure title="합성 30초 마이크 시험"><StaffVoiceTrial api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure></div>}
    </div></section></div>}
  </main></>
}
