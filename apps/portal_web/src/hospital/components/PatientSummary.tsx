import type { HospitalFact, HospitalMessage } from '../../shared/types/domain'
import { CONTEXT_LABELS } from '../../shared/types/constants'
import { EmptyState } from '../../shared/components/EmptyState'
import { formatHospitalTime } from '../utils/format'
import type { PortalLoadState } from '../hooks/useHospitalPortal'

export type PatientSummaryLoad = {
  states?: { facts: PortalLoadState; messages: PortalLoadState }
  errors?: { facts: string; messages: string }
  onRetry?: () => void
}
export function PatientSummary({ facts, messages, states, errors, onRetry }: { facts: HospitalFact[]; messages: HospitalMessage[] } & PatientSummaryLoad) {
  return <div><h3>직원 승인 사실</h3>{states?.facts === 'loading' ? <p role="status">직원 승인 사실을 불러오는 중…</p> : states?.facts === 'error' ? <div role="alert"><p>{errors?.facts || '직원 승인 사실을 읽지 못했습니다.'}</p><button onClick={onRetry}>다시 시도</button></div> : !facts.length ? <EmptyState>현재 유효한 병원 사실이 없습니다.</EmptyState> : <ul className="item-list">{facts.map(f => <li className="item summary-row" key={f.fact_id}><div className="item-title">{CONTEXT_LABELS[f.category] ?? f.category}</div><p>{f.content}</p><div className="item-meta">확인 {formatHospitalTime(f.verified_at)}</div></li>)}</ul>}<h3>승인 메시지</h3>{states?.messages === 'loading' ? <p role="status">승인 메시지를 불러오는 중…</p> : states?.messages === 'error' ? <div role="alert"><p>{errors?.messages || '승인 메시지를 읽지 못했습니다.'}</p><button onClick={onRetry}>다시 시도</button></div> : !messages.length ? <EmptyState>이번 입원의 승인 메시지가 없습니다.</EmptyState> : <ul className="item-list">{messages.map((m, i) => <li className="item" id={m.message_id ? `message-${m.message_id}` : undefined} key={m.message_id ?? i}><p>{m.approved_text}</p><div className="item-meta">{m.delivery_status === 'pending' ? '전달 대기' : m.delivery_status === 'delivered' ? '전달됨' : '취소됨'} · {formatHospitalTime(m.due_at)}</div></li>)}</ul>}</div>
}
