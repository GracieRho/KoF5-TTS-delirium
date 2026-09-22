import { useState, type FormEvent } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import type { Patient } from '../../shared/types/domain'
import { UUID } from '../../shared/types/constants'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'

export function DevicePairing({ api, token, patient }: { api: SupabaseRest; token: string; patient: Patient }) {
  const [device, setDevice] = useState(''); const [status, setStatus] = useState(''); const [busy, setBusy] = useState(false)
  async function submit(event: FormEvent) { event.preventDefault(); const id = device.trim().toLowerCase(); if (!UUID.test(id) || !patient.encounter_id) return setStatus('토큰이 아닌 iPad Auth 사용자 ID(UUID)를 입력하세요.'); setBusy(true); try { await hospitalApi.pair(api, token, { device_user_id: id, patient_id: patient.patient_id, encounter_id: patient.encounter_id, expires_at: new Date(Date.now() + 7 * 60 * 60 * 1000).toISOString() }); setDevice(''); setStatus('합성 iPad 연결을 기록했습니다. 실제 환자 시험에는 사용할 수 없습니다.') } catch { setStatus('연결하지 못했습니다. 중복 연결과 담당 권한을 확인하세요.') } finally { setBusy(false) } }
  return <form className="form-stack" onSubmit={submit}><label>iPad Auth 사용자 ID<input required maxLength={36} placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" value={device} onChange={e => setDevice(e.target.value)}/></label><button disabled={busy || !patient.encounter_id}>합성 iPad 연결</button><StatusMessage>{status}</StatusMessage></form>
}
