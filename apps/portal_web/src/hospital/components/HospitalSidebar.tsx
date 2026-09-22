import type { Patient } from '../../shared/types/domain'
import { PatientList } from './PatientList'

export type HospitalView = 'patients' | 'queue'

export function HospitalSidebar({ view, patients, selectedId, queueCount, onView, onSelect, onRegister, onSignOut }: { view: HospitalView; patients: Patient[]; selectedId?: string; queueCount: number; onView: (view: HospitalView) => void; onSelect: (id: string) => void; onRegister: () => void; onSignOut: () => void }) {
  return <aside className="hospital-sidebar">
    <div className="sidebar-heading"><h2>병원 업무</h2><button type="button" onClick={onSignOut}>로그아웃</button></div>
    <nav className="side-nav" aria-label="병원 주요 업무">
      <button type="button" aria-pressed={view === 'patients'} onClick={() => onView('patients')}>담당 환자</button>
      <button type="button" aria-pressed={view === 'queue'} onClick={() => onView('queue')}>전체 전달 대기 <span>{queueCount}</span></button>
      <button type="button" onClick={onRegister}>환자 등록</button>
    </nav>
    {view === 'patients' && <div className="sidebar-patients"><PatientList patients={patients} selectedId={selectedId} onSelect={onSelect}/></div>}
  </aside>
}
