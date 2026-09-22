import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { RequestEpoch } from '../../shared/hooks/requestEpoch'
import type { FamilyFact, GuardianLink } from '../../shared/types/domain'
import { guardianApi, validLink } from '../api/guardianApi'

export function useGuardianPortal() {
  const { api, token } = useAuth(); const requests = useRef(new RequestEpoch()); const [links, setLinks] = useState<GuardianLink[]>([]); const [facts, setFacts] = useState<FamilyFact[]>([]); const [patientId, setPatientId] = useState(''); const [busy, setBusy] = useState(false); const [status, setStatus] = useState('')
  const activeLinks = useMemo(() => links.filter(link => validLink(link)), [links])
  const loadFacts = useCallback(async (id: string) => {
    if (!api || !token || !id) return
    const owner = requests.current.begin(); setFacts([]); setBusy(true)
    try { const rows = await guardianApi.facts(api, token, id); if (!requests.current.owns(owner)) return; setFacts(rows); setStatus('가족 기억을 불러왔습니다.') }
    catch { if (requests.current.owns(owner)) { setFacts([]); setStatus('가족 기억을 읽지 못했습니다. 연결과 권한을 확인하세요.') } }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }, [api, token])
  useEffect(() => {
    requests.current.invalidate(); setLinks([]); setFacts([]); setPatientId('')
    if (!api || !token) return
    const owner = requests.current.begin(); setBusy(true)
    void guardianApi.links(api, token).then(rows => {
      if (!requests.current.owns(owner)) return
      setLinks(rows); const first = rows.find(link => validLink(link))?.patient_id ?? ''; setPatientId(first); setBusy(false)
      if (first) void loadFacts(first)
    }).catch(() => { if (requests.current.owns(owner)) { setBusy(false); setStatus('환자 연결을 확인하지 못했습니다.') } })
    return () => requests.current.invalidate()
  }, [api, token, loadFacts])
  async function selectPatient(id: string) { requests.current.invalidate(); setPatientId(id); setFacts([]); setStatus('선택한 연결을 확인하고 있습니다.'); await loadFacts(id) }
  async function save(category: string, content: string, factId?: string) {
    if (!api || !token || !patientId) return
    const owner = requests.current.begin(); setBusy(true)
    try { if (factId) await guardianApi.updateFact(api, token, patientId, factId, category, content); else await guardianApi.createFact(api, token, patientId, category, content); if (!requests.current.owns(owner)) return; await loadFacts(patientId); setStatus(factId ? '기억을 수정했습니다.' : '기억을 저장했습니다.') }
    catch { if (requests.current.owns(owner)) setStatus('기억을 저장하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도하세요.') }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }
  return { links, activeLinks, facts, patientId, busy, status, selectPatient, save }
}
