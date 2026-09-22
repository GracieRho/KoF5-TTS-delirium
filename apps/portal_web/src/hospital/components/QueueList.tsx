import type { HospitalMessage, Patient } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'
import { formatHospitalTime } from '../utils/format'

export function QueueList({ messages, patients }: { messages: HospitalMessage[]; patients: Patient[] }) {
  if (!messages.length) return <EmptyState>현재 전달 대기 메시지가 없습니다.</EmptyState>
  return <ul className="queue-list">{messages.map((message, index) => {
    const patient = patients.find(row => row.patient_id === message.patient_id)
    return <li className="queue-row" key={`${message.encounter_id}-${index}`}><div><strong>{patient?.staff_display_name ?? '환자 확인 필요'}</strong><span>{patient ? `${patient.ward_ref || '병동 미확인'} ${patient.room_ref || ''}` : message.encounter_id}</span></div><p>{message.approved_text}</p><time>{formatHospitalTime(message.due_at)}</time></li>
  })}</ul>
}
