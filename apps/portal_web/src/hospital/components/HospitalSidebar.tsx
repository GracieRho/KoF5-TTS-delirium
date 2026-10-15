import type { Patient } from '../../shared/types/domain'
import { PatientList } from './PatientList'

export type HospitalView = 'patients' | 'queue'
export function HospitalSidebar({ patients, selectedId, onSelect }: { patients: Patient[]; selectedId?: string; onSelect: (id: string) => void }) {
  return <aside className="hospital-sidebar"><div className="sidebar-heading"><h2>담당 환자</h2></div><div className="sidebar-patients"><PatientList patients={patients} selectedId={selectedId} onSelect={onSelect} /></div></aside>
}
