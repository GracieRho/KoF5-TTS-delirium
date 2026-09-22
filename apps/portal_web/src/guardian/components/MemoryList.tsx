import type { FamilyFact } from '../../shared/types/domain'
import { FAMILY_LABELS } from '../../shared/types/constants'
import { EmptyState } from '../../shared/components/EmptyState'

export function MemoryList({ facts, category, onEdit }: { facts: FamilyFact[]; category: 'memory' | 'avoid'; onEdit: (fact: FamilyFact) => void }) {
  const rows = facts.filter(fact => category === 'avoid' ? fact.category === 'avoid_topic' : fact.category !== 'avoid_topic')
  if (!rows.length) return <EmptyState>{category === 'avoid' ? '피해야 할 이야기가 없습니다.' : '아직 남긴 가족 기억이 없습니다.'}</EmptyState>
  return <ul className="item-list">{rows.map(fact => <li className="item" key={fact.fact_id}><div className="item-title">{FAMILY_LABELS[fact.category] ?? fact.category}</div><p>{fact.content}</p><button type="button" onClick={() => onEdit(fact)}>수정</button></li>)}</ul>
}
