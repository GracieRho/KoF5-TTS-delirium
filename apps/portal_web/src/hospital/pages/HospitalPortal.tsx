import { useEffect, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { usePortalConnection } from '../../shared/hooks/usePortalConnection'
import { SYNTHETIC_PATIENT_ID } from '../../shared/types/constants'
import { AppHeader } from '../../shared/components/AppHeader'
import { Disclosure } from '../../shared/components/Disclosure'
import { LoginForm } from '../../shared/components/LoginForm'
import { Panel } from '../../shared/components/Panel'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { AlertDashboard } from '../components/AlertDashboard'
import { ContextApproval } from '../components/ContextApproval'
import { DevicePairing } from '../components/DevicePairing'
import { HospitalTabs, type HospitalTab } from '../components/HospitalTabs'
import { HospitalSidebar, type HospitalView } from '../components/HospitalSidebar'
import { MessageApproval } from '../components/MessageApproval'
import { PatientRegistration } from '../components/PatientRegistration'
import { PatientSummary } from '../components/PatientSummary'
import { QueueList } from '../components/QueueList'
import { StaffVoiceTrial } from '../components/StaffVoiceTrial'
import { TranscriptList } from '../components/TranscriptList'
import { useHospitalPortal } from '../hooks/useHospitalPortal'

export function HospitalPortal() {
  const auth = useAuth(); const connection = usePortalConnection(); const portal = useHospitalPortal(); const [tab, setTab] = useState<HospitalTab>('summary'); const [view, setView] = useState<HospitalView>('patients'); const [registrationOpen, setRegistrationOpen] = useState(false); const synthetic = portal.selected?.patient_id === SYNTHETIC_PATIENT_ID
  useEffect(() => { if (!synthetic && tab !== 'summary') setTab('summary') }, [synthetic, tab])
  const showWorkspace = view === 'queue' || Boolean(portal.selected)
  return <><AppHeader area="병원"/><main className="page hospital-page">
    {!auth.token ? <div className="auth-layout"><Panel title="병원 직원 로그인" description="기관에서 자격을 검증한 계정으로 로그인하세요."><LoginForm kind="병원 직원" ready={connection.ready} onLogin={auth.signIn}/></Panel><Panel className="boundary" title="승인 범위"><p>가족 기억은 보호자 화면에서 관리합니다. 병실·검사·예약 메시지는 현재 입원과 직원 승인 상태를 따로 확인합니다.</p><p className="compact">실제 환자 사용은 기관 승인, 동의, 환자 거부 및 개인정보 처리 절차가 완료된 뒤에만 시작합니다.</p></Panel></div> :
    <><div className={`hospital-grid ${showWorkspace ? 'show-workspace' : ''}`}><HospitalSidebar view={view} patients={portal.patients} selectedId={portal.selected?.patient_id} queueCount={portal.queue.length} onView={next => { setView(next); if (next === 'patients') setTab('summary') }} onSelect={id => { setView('patients'); setTab('summary'); void portal.select(id) }} onRegister={() => setRegistrationOpen(true)} onSignOut={auth.signOut}/><section className="hospital-workspace">
      <button className="mobile-back" type="button" onClick={() => { setView('patients'); setTab('summary') }}>병원 업무로</button>
      {view === 'queue' ? <><div className="workspace-heading"><div><h1>전체 전달 대기</h1><p>{portal.queue.length}건 · 담당 환자 전체</p></div></div><QueueList messages={portal.queue} patients={portal.patients}/></> : portal.selected ? <><div className="workspace-heading"><div><h1>{portal.selected.staff_display_name}</h1><p>{portal.selected.ehr_patient_ref} · {portal.selected.encounter_id ? `${portal.selected.ward_ref || '병동 미확인'} ${portal.selected.room_ref || ''} ${portal.selected.bed_ref || ''}` : '현재 입원 없음'}</p></div></div><HospitalTabs value={tab} onChange={setTab} synthetic={synthetic}/><div role="tabpanel" id={`hospital-panel-${tab}`} aria-labelledby={`hospital-tab-${tab}`} tabIndex={0}>
        {tab === 'summary' && <PatientSummary facts={portal.facts} messages={portal.messages}/>}
        {synthetic && portal.api && portal.token && tab === 'messages' && <MessageApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/>}
        {synthetic && portal.api && portal.token && tab === 'context' && <ContextApproval api={portal.api} token={portal.token} userId={auth.userId} patient={portal.selected}/>}
        {synthetic && portal.api && portal.token && tab === 'operations' && <div className="stack"><Disclosure title="오늘의 합성 대화 전사" open><TranscriptList api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure><Disclosure title="합성 위험 발화 보조 경고"><AlertDashboard api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure><Disclosure title="합성 iPad 연결 시험"><DevicePairing api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure><Disclosure title="합성 30초 마이크 시험"><StaffVoiceTrial api={portal.api} token={portal.token} patient={portal.selected}/></Disclosure></div>}
      </div></> : <p className="empty-state">왼쪽에서 담당 환자를 선택하세요.</p>}
      <StatusMessage>{portal.status}</StatusMessage>
    </section></div><ResponsiveSheet open={registrationOpen} title="환자 등록" onClose={() => setRegistrationOpen(false)}>{portal.api && portal.token && <PatientRegistration api={portal.api} token={portal.token} readiness={portal.readiness} onDone={async () => { await portal.refresh(); setRegistrationOpen(false) }}/>}</ResponsiveSheet></>}
  </main></>
}
