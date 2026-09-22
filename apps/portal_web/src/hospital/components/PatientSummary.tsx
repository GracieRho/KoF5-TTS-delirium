import type { HospitalFact, HospitalMessage, Patient } from '../../shared/types/domain'
import { CONTEXT_LABELS } from '../../shared/types/constants'
import { EmptyState } from '../../shared/components/EmptyState'
import { encounterLabel, formatHospitalTime } from '../utils/format'

export function PatientSummary({ patient, facts, messages }: { patient: Patient; facts: HospitalFact[]; messages: HospitalMessage[] }) {
  return <div><div className="item"><strong>{patient.staff_display_name}</strong><div className="item-meta">{patient.ehr_patient_ref} · {encounterLabel(patient)}</div></div><h3>직원 승인 사실</h3>{!facts.length ? <EmptyState>현재 유효한 병원 사실이 없습니다.</EmptyState> : <ul className="item-list">{facts.map(f => <li className="item" key={f.fact_id}><div className="item-title">{CONTEXT_LABELS[f.category] ?? f.category}</div><p>{f.content}</p><div className="item-meta">확인 {formatHospitalTime(f.verified_at)}</div></li>)}</ul>}<h3>승인 메시지</h3>{!messages.length ? <EmptyState>이번 입원의 승인 메시지가 없습니다.</EmptyState> : <ul className="item-list">{messages.map((m, i) => <li className="item" key={m.message_id ?? i}><p>{m.approved_text}</p><div className="item-meta">{m.delivery_status === 'pending' ? '전달 대기' : m.delivery_status === 'delivered' ? '전달됨' : '취소됨'} · {formatHospitalTime(m.due_at)}</div></li>)}</ul>}</div>
}
