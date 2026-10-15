import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { RequestEpoch } from '../../shared/hooks/requestEpoch'
import type { HospitalFact, HospitalMessage, HospitalReadiness, Patient } from '../../shared/types/domain'
import { hospitalApi } from '../api/hospitalApi'

export type PortalLoadState = 'loading' | 'error' | 'ready'
type Resource = 'patients' | 'readiness' | 'queue' | 'facts' | 'messages'
const INITIAL_STATES: Record<Resource, PortalLoadState> = { patients: 'loading', readiness: 'loading', queue: 'loading', facts: 'loading', messages: 'loading' }
const ERRORS: Record<Resource, string> = { patients: '담당 환자를 읽지 못했습니다.', readiness: '환자 등록 권한을 확인하지 못했습니다.', queue: '전달 대기 메시지를 읽지 못했습니다.', facts: '직원 승인 사실을 읽지 못했습니다.', messages: '승인 메시지를 읽지 못했습니다.' }

export function useHospitalPortal() {
  const { api, token } = useAuth()
  const requests = useRef(new RequestEpoch()), detailRequests = useRef(new RequestEpoch())
  const [patients, setPatients] = useState<Patient[]>([]), [readiness, setReadiness] = useState<HospitalReadiness[]>([]), [queue, setQueue] = useState<HospitalMessage[]>([])
  const [selectedId, setSelectedId] = useState(''), [facts, setFacts] = useState<HospitalFact[]>([]), [messages, setMessages] = useState<HospitalMessage[]>([])
  const [loadState, setLoadState] = useState(INITIAL_STATES)
  const selected = useMemo(() => patients.find(row => row.patient_id === selectedId) ?? null, [patients, selectedId])
  const load = useCallback(async <T,>(resource: Resource, request: Promise<T>, update: (value: T) => void, epoch: RequestEpoch, owner: number) => {
    setLoadState(previous => ({ ...previous, [resource]: 'loading' }))
    try {
      const value = await request
      if (!epoch.owns(owner)) return
      update(value)
      setLoadState(previous => ({ ...previous, [resource]: 'ready' }))
    } catch {
      if (epoch.owns(owner)) setLoadState(previous => ({ ...previous, [resource]: 'error' }))
    }
  }, [])
  const refresh = useCallback(async () => {
    if (!api || !token) return
    const epoch = requests.current, owner = epoch.begin()
    await Promise.all([
      load('patients', hospitalApi.patients(api, token), setPatients, epoch, owner),
      load('readiness', hospitalApi.readiness(api, token), setReadiness, epoch, owner),
      load('queue', hospitalApi.queue(api, token), setQueue, epoch, owner),
    ])
  }, [api, token, load])
  const select = useCallback(async (id: string) => {
    if (!api || !token) return
    const epoch = detailRequests.current, owner = epoch.begin()
    setSelectedId(id); setFacts([]); setMessages([])
    await Promise.all([
      load('facts', hospitalApi.facts(api, token, id), setFacts, epoch, owner),
      load('messages', hospitalApi.messages(api, token, id), setMessages, epoch, owner),
    ])
  }, [api, token, load])
  useEffect(() => {
    requests.current.invalidate(); detailRequests.current.invalidate()
    setPatients([]); setReadiness([]); setQueue([]); setSelectedId(''); setFacts([]); setMessages([]); setLoadState(INITIAL_STATES)
    if (token) void refresh()
    return () => { requests.current.invalidate(); detailRequests.current.invalidate() }
  }, [token, refresh])
  const errors = Object.fromEntries(Object.entries(loadState).map(([key, state]) => [key, state === 'error' ? ERRORS[key as Resource] : ''])) as Record<Resource, string>
  const busy = Object.entries(loadState).some(([key, state]) => state === 'loading' && (selectedId || (key !== 'facts' && key !== 'messages')))
  return { api, token, patients, readiness, queue, selected, facts, messages, status: '', busy, loadState, errors, refresh, select, reloadSelected: () => select(selectedId) }
}
