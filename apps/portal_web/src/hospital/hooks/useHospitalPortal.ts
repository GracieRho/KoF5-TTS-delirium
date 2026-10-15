import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { RequestEpoch } from '../../shared/hooks/requestEpoch'
import type { HospitalFact, HospitalMessage, HospitalReadiness, Patient } from '../../shared/types/domain'
import { hospitalApi } from '../api/hospitalApi'

export function useHospitalPortal() {
  const { api, token } = useAuth(); const requests = useRef(new RequestEpoch()); const [patients, setPatients] = useState<Patient[]>([]); const [readiness, setReadiness] = useState<HospitalReadiness[]>([]); const [queue, setQueue] = useState<HospitalMessage[]>([]); const [selectedId, setSelectedId] = useState(''); const [facts, setFacts] = useState<HospitalFact[]>([]); const [messages, setMessages] = useState<HospitalMessage[]>([]); const [status, setStatus] = useState(''); const [busy, setBusy] = useState(false)
  const selected = useMemo(() => patients.find(row => row.patient_id === selectedId) ?? null, [patients, selectedId])
  const refresh = useCallback(async () => {
    if (!api || !token) return
    const owner = requests.current.begin(); setBusy(true)
    try { const [p, r, q] = await Promise.all([hospitalApi.patients(api, token), hospitalApi.readiness(api, token), hospitalApi.queue(api, token)]); if (!requests.current.owns(owner)) return; setPatients(p); setReadiness(r); setQueue(q); setStatus('') }
    catch { if (requests.current.owns(owner)) setStatus('담당 환자 정보를 읽지 못했습니다.') }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }, [api, token])
  useEffect(() => { requests.current.invalidate(); setPatients([]); setReadiness([]); setQueue([]); setSelectedId(''); setFacts([]); setMessages([]); if (token) void refresh(); return () => requests.current.invalidate() }, [token, refresh])
  async function select(id: string) {
    if (!api || !token) return
    const owner = requests.current.begin(); setSelectedId(id); setFacts([]); setMessages([]); setStatus(''); setBusy(true)
    try { const [f, m] = await Promise.all([hospitalApi.facts(api, token, id), hospitalApi.messages(api, token, id)]); if (!requests.current.owns(owner)) return; setFacts(f); setMessages(m); setStatus('') }
    catch { if (requests.current.owns(owner)) { setFacts([]); setMessages([]); setStatus('현재 입원 정보를 읽지 못했습니다.') } }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }
  return { api, token, patients, readiness, queue, selected, facts, messages, status, busy, refresh, select }
}
