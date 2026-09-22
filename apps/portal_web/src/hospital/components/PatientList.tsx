import { useMemo, useState } from 'react'
import type { Patient } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'

export function PatientList({ patients, selectedId, onSelect }: { patients: Patient[]; selectedId?: string; onSelect: (id: string) => void }) {
  const [query, setQuery] = useState(''); const rows = useMemo(() => { const q = query.trim().toLowerCase(); return !q ? patients : patients.filter(p => [p.staff_display_name,p.ehr_patient_ref,p.ward_ref,p.room_ref].some(v => v?.toLowerCase().includes(q))) }, [patients, query])
  return <><label className="field">이름·환자 번호·병동 검색<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="담당 환자 찾기"/></label>{!rows.length ? <EmptyState>조회 가능한 담당 환자가 없습니다.</EmptyState> : <ul className="item-list">{rows.map(patient => <li key={patient.patient_id}><button className="patient-button" aria-pressed={selectedId === patient.patient_id} onClick={() => onSelect(patient.patient_id)}><strong>{patient.staff_display_name}</strong><span className="item-meta">{patient.ehr_patient_ref} · {patient.encounter_id ? `${patient.ward_ref || '병동 미확인'} ${patient.room_ref || ''}` : '현재 입원 없음'}</span></button></li>)}</ul>}</>
}
