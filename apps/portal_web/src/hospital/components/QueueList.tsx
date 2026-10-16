import type { HospitalMessage, Patient } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'
import { formatHospitalTime } from '../utils/format'
import type { PortalLoadState } from '../hooks/useHospitalPortal'

export function QueueList({ messages, patients, state, error, onRetry, onOpen }: { messages: HospitalMessage[]; patients: Patient[]; state?: PortalLoadState; error?: string; onRetry?: () => void; onOpen?: (message: HospitalMessage) => void }) {
  if (state === 'loading') return <p role="status">전달 대기 메시지를 불러오는 중…</p>
  if (state === 'error') return <div role="alert"><p>{error || '전달 대기 메시지를 읽지 못했습니다.'}</p><button onClick={onRetry}>다시 시도</button></div>
  if (!messages.length) return <EmptyState>현재 전달 대기 메시지가 없습니다.</EmptyState>
  return <ul className="queue-list">{messages.map((message, index) => {
    const patient = patients.find(row => row.patient_id === message.patient_id)
    return <li className="queue-row" key={message.message_id ?? `${message.encounter_id}-${index}`}><div><strong>{patient?.staff_display_name ?? '환자 확인 필요'}</strong><span>{patient ? `${patient.ward_ref || '병동 미확인'} ${patient.room_ref || ''}` : message.encounter_id}</span></div><p>{message.approved_text}</p><time>{formatHospitalTime(message.due_at)}</time>{onOpen && <button disabled={!patient} onClick={() => onOpen(message)}>메시지 확인</button>}</li>
  })}</ul>
}
