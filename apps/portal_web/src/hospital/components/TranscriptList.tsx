import { useEffect, useState } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import type { Patient, Transcript } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'
import { formatHospitalTime } from '../utils/format'

export function TranscriptList({ api, token, patient }: { api: SupabaseRest; token: string; patient: Patient }) {
  const [rows, setRows] = useState<Transcript[]>([]); const [error, setError] = useState(false)
  useEffect(() => { void hospitalApi.transcripts(api, token, patient).then(setRows).catch(() => setError(true)) }, [api, token, patient])
  if (error) return <StatusMessage tone="warning">오늘의 합성 전사를 읽지 못했습니다.</StatusMessage>
  return !rows.length ? <EmptyState>오늘 조회 가능한 합성 대화 전사가 없습니다.</EmptyState> : <ul className="item-list">{rows.map(row => <li className="item" key={row.turn_id}><p>{row.transcript}</p><div className="item-meta">{formatHospitalTime(row.captured_at)}</div></li>)}</ul>
}
