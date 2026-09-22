import type { HospitalMessage } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'
import { formatHospitalTime } from '../utils/format'

export function QueueList({ messages }: { messages: HospitalMessage[] }) { return !messages.length ? <EmptyState>현재 전달 대기 메시지가 없습니다.</EmptyState> : <ul className="item-list">{messages.map((message, index) => <li className="item" key={`${message.encounter_id}-${index}`}><div className="item-title">전달 대기</div><p>{message.approved_text}</p><div className="item-meta">예정 {formatHospitalTime(message.due_at)}</div></li>)}</ul> }
