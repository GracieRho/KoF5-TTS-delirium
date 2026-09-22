import { useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { usePortalConnection } from '../../shared/hooks/usePortalConnection'
import { SYNTHETIC_PATIENT_ID } from '../../shared/types/constants'
import type { FamilyFact } from '../../shared/types/domain'
import { AppHeader } from '../../shared/components/AppHeader'
import { LoginForm } from '../../shared/components/LoginForm'
import { Panel } from '../../shared/components/Panel'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { GuardianLinks } from '../components/GuardianLinks'
import { MemoryForm } from '../components/MemoryForm'
import { MemoryList } from '../components/MemoryList'
import { VoiceTrial } from '../components/VoiceTrial'
import { useGuardianPortal } from '../hooks/useGuardianPortal'

export function GuardianPortal() {
  const auth = useAuth(); const connection = usePortalConnection(); const portal = useGuardianPortal(); const [editing, setEditing] = useState<FamilyFact | null>(null)
  return <><AppHeader area="보호자"/><main className="page guardian-page">
    {!auth.token ? <div className="guardian-flow"><Panel title="보호자 로그인" description="병원에서 환자 연결을 확인한 계정으로 로그인하세요."><LoginForm kind="보호자" ready={connection.ready} onLogin={auth.signIn} onSignup={auth.signUp}/></Panel><Panel className="boundary" title="입력 전에 확인해요"><p>환자 번호·생년월일·병실은 보이지 않습니다. 의료 정보나 확인되지 않은 퇴원 날짜도 기억에 적지 마세요.</p><p className="compact">실제 환자 사용은 기관 승인과 동의·환자 거부·개인정보 처리 절차가 끝난 뒤에만 시작합니다.</p></Panel></div> :
    <div className="guardian-flow"><Panel title="연결된 환자" actions={<button onClick={auth.signOut}>로그아웃</button>}><GuardianLinks links={portal.links} selected={portal.patientId} onSelect={id => void portal.selectPatient(id)}/><StatusMessage>{portal.status}</StatusMessage></Panel><Panel title="가족의 기억"><MemoryList facts={portal.facts} category="memory" onEdit={setEditing}/></Panel><Panel title="피해야 할 이야기"><MemoryList facts={portal.facts} category="avoid" onEdit={setEditing}/></Panel><Panel title={editing ? '기억 수정' : '새 기억'}><MemoryForm editing={editing} busy={portal.busy} onSave={async (...args) => { await portal.save(...args); setEditing(null) }} onCancel={() => setEditing(null)}/></Panel>{portal.patientId === SYNTHETIC_PATIENT_ID && auth.token && <Panel title="음성 등록 시험" description="합성 시험 조건과 본인 음성 확인을 먼저 점검합니다."><VoiceTrial patientId={portal.patientId} token={auth.token}/></Panel>}</div>}
  </main></>
}
