import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import type { FamilyFact, GuardianLink } from '../../shared/types/domain'
import { guardianApi, validLink } from '../api/guardianApi'

export function useGuardianPortal() {
  const { api, token, signOut } = useAuth(); const [links, setLinks] = useState<GuardianLink[]>([]); const [facts, setFacts] = useState<FamilyFact[]>([]); const [patientId, setPatientId] = useState(''); const [busy, setBusy] = useState(false); const [status, setStatus] = useState('')
  const activeLinks = useMemo(() => links.filter(link => validLink(link)), [links])
  const loadFacts = useCallback(async (id: string) => { if (!api || !token || !id) return; setBusy(true); try { setFacts(await guardianApi.facts(api, token, id)); setStatus('가족 기억을 불러왔습니다.') } catch { setFacts([]); setStatus('가족 기억을 읽지 못했습니다. 연결과 권한을 확인하세요.') } finally { setBusy(false) } }, [api, token])
  useEffect(() => { if (!api || !token) return; void guardianApi.links(api, token).then(rows => { setLinks(rows); const first = rows.find(validLink)?.patient_id ?? ''; setPatientId(first); if (first) void loadFacts(first) }).catch(() => { signOut(); setStatus('환자 연결을 확인하지 못해 로그아웃했습니다.') }) }, [api, token, loadFacts])
  async function selectPatient(id: string) { setPatientId(id); await loadFacts(id) }
  async function save(category: string, content: string, factId?: string) { if (!api || !token || !patientId) return; setBusy(true); try { if (factId) await guardianApi.updateFact(api, token, patientId, factId, category, content); else await guardianApi.createFact(api, token, patientId, category, content); await loadFacts(patientId); setStatus(factId ? '기억을 수정했습니다.' : '기억을 저장했습니다.') } catch { setStatus('기억을 저장하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도하세요.') } finally { setBusy(false) } }
  return { links, activeLinks, facts, patientId, busy, status, selectPatient, save }
}
