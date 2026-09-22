import type { GuardianLink } from '../../shared/types/domain'
import { validLink } from '../api/guardianApi'

export function GuardianLinks({ links, selected, onSelect }: { links: GuardianLink[]; selected: string; onSelect: (id: string) => void }) {
  return <><ul className="item-list" aria-label="보호자 연결">{links.map(link => <li className="item" key={`${link.patient_id}-${link.relationship}`}><strong>{link.relationship || '보호자'}</strong><div className="item-meta">{validLink(link) ? '현재 연결 확인됨' : '연결 확인 대기'} · 끝자리 {link.patient_id.slice(-6)}</div></li>)}</ul>
    <label className="field">기억을 남길 연결<select value={selected} onChange={e => onSelect(e.target.value)}>{links.filter(link => validLink(link)).map(link => <option key={link.patient_id} value={link.patient_id}>{link.relationship || '보호자'} · {link.patient_id.slice(-6)}</option>)}</select></label></>
}
