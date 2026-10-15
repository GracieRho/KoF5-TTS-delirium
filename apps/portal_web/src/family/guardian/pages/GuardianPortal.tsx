import { useEffect, useState } from 'react'
import { useAuth } from '../../../shared/auth/AuthContext'
import { Panel } from '../../../shared/components/Panel'
import type { GuardianLink } from '../../../shared/types/domain'
import { guardianApi, validLink } from '../api/guardianApi'

export function GuardianPortal() {
  const { api, token } = useAuth()
  const [links, setLinks] = useState<GuardianLink[]>([])
  const [error, setError] = useState(false)
  useEffect(() => {
    let active = true
    setLinks([]); setError(false)
    if (api && token) void guardianApi.links(api, token).then(rows => {
      if (active) setLinks(rows)
    }).catch(() => { if (active) setError(true) })
    return () => { active = false }
  }, [api, token])
  return <section className="stack">
    <div className="section-heading"><div><h1>병원 연결</h1><p>병원에서 확인한 가족 연결 상태를 볼 수 있어요.</p></div></div>
    <Panel title="연결된 가족">
      {error ? <p role="alert">가족 연결을 확인하지 못했습니다. 다시 연결해주세요.</p> :
      <ul className="item-list">{links.map(link => <li className="item" key={link.patient_id}><strong>{link.relationship}</strong><p>{validLink(link) ? '병원 연결 확인됨' : '병원 확인 필요'}</p></li>)}</ul>}
    </Panel>
    <Panel title="가족의 기억은 한곳에서"><p>소개와 기억은 왼쪽 ‘가족의 기억’에서 관리하고, ‘대화해보기’에서 등록한 목소리로 사용해요.</p><p className="compact">병원에서 승인한 안내와 가족이 작성한 기억은 별도로 관리됩니다.</p></Panel>
  </section>
}
