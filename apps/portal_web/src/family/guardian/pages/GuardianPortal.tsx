import { HelpTooltip } from '../../../shared/components/HelpTooltip'
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
    <div className="section-heading"><div><div className="heading-with-help"><h1>병원 연결</h1><HelpTooltip label="병원 연결 도움말">병원에서 확인한 가족 연결 상태입니다. 소개와 기억은 가족의 기억에서 관리합니다.</HelpTooltip></div></div></div>
    <Panel title="연결된 가족">
      {error ? <p role="alert">가족 연결을 확인하지 못했습니다. 다시 연결해주세요.</p> :
      <ul className="item-list">{links.map(link => <li className="item" key={link.patient_id}><strong>{link.relationship}</strong><p>{validLink(link) ? '병원 연결 확인됨' : '병원 확인 필요'}</p></li>)}</ul>}
    </Panel>

  </section>
}
