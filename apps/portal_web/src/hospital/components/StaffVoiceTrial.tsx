import { useEffect, useRef, useState } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import { RequestEpoch, retainOwnedStream } from '../../shared/hooks/requestEpoch'
import type { Patient } from '../../shared/types/domain'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'

export function StaffVoiceTrial({ api, token, patient }: { api: SupabaseRest; token: string; patient: Patient }) {
  const epoch = useRef(new RequestEpoch()); const mounted = useRef(true); const stream = useRef<MediaStream | null>(null); const timer = useRef<number | null>(null); const startedRef = useRef(0)
  const [active, setActive] = useState(false); const [ready, setReady] = useState(false); const [confirmed, setConfirmed] = useState(false); const [duration, setDuration] = useState(0); const [status, setStatus] = useState('합성 준비 조건을 확인하고 있습니다.')
  function release(reason = '직원이 중단') { if (timer.current) window.clearTimeout(timer.current); timer.current = null; stream.current?.getTracks().forEach(track => track.stop()); stream.current = null; if (mounted.current) { if (startedRef.current) setDuration(Math.min(30, (Date.now() - startedRef.current) / 1000)); setActive(false); setStatus(`${reason}. 마이크를 중단하고 오디오 참조를 해제했습니다. 추가 보관·전송하지 않습니다.`) } }
  async function checkReady() { const owner = epoch.current.begin(); try { const rows = await hospitalApi.rpc<Array<{ patient_id: string; ready: boolean }>>(api, token, 'synthetic_voice_enrollment_ready'); if (!epoch.current.owns(owner) || !mounted.current) return; const ok = rows.length === 1 && rows[0].patient_id === patient.patient_id && rows[0].ready === true; setReady(ok); setStatus(ok ? '시험자 본인 음성으로만 30초 이내 마이크 시험을 시작할 수 있습니다.' : '합성 준비 조건이 충족되지 않았습니다.') } catch { if (epoch.current.owns(owner) && mounted.current) { setReady(false); setStatus('합성 음성 시험 준비 결과를 확인하지 못했습니다.') } } }
  useEffect(() => { mounted.current = true; epoch.current.invalidate(); release('환자 변경'); setConfirmed(false); const hide = () => { if (document.hidden) { epoch.current.invalidate(); release('화면 숨김'); setConfirmed(false) } }; document.addEventListener('visibilitychange', hide); void checkReady(); return () => { document.removeEventListener('visibilitychange', hide); mounted.current = false; epoch.current.invalidate(); release('화면 이동') } }, [api, token, patient])
  function changeConfirmed(value: boolean) { setConfirmed(value); if (!value) { epoch.current.invalidate(); release('본인 음성 확인 해제') } }
  async function start() {
    if (!ready || !confirmed || active) return
    const owner = epoch.current.begin(); setStatus('직원 자격을 다시 확인하고 마이크 권한을 요청합니다.'); let media: MediaStream | null = null
    try {
      const rows = await hospitalApi.rpc<Array<{ patient_id: string; ready: boolean }>>(api, token, 'synthetic_voice_enrollment_ready')
      if (!epoch.current.owns(owner) || !mounted.current || !confirmed || document.hidden || rows.length !== 1 || rows[0].patient_id !== patient.patient_id || rows[0].ready !== true) return
      media = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
      if (!retainOwnedStream(epoch.current, owner, media, mounted.current && confirmed && !document.hidden)) return
      stream.current = media; startedRef.current = Date.now(); setDuration(0); setActive(true); setStatus('시험자 본인 음성을 메모리에서만 녹음 중입니다.'); timer.current = window.setTimeout(() => { if (epoch.current.owns(owner)) release('30초 시험 상한 도달') }, 30000)
    } catch { media?.getTracks().forEach(track => track.stop()); if (epoch.current.owns(owner) && mounted.current) release('마이크 권한 또는 브라우저 녹음 기능 확인 실패') }
  }
  return <div><p className="compact">담당 직원이 자신의 목소리로만 시험합니다. 실제 환자·주변인 음성은 녹음하지 마세요.</p><label className="field"><span><input type="checkbox" checked={confirmed} onChange={event => changeConfirmed(event.target.checked)} style={{ width: 'auto', minHeight: 0 }} /> 이 시험은 직원인 내 목소리만 사용합니다.</span></label><div className="button-row"><button disabled={!ready || !confirmed || active} onClick={() => void start()}>본인 음성 시험 시작</button><button disabled={!active} onClick={() => { epoch.current.invalidate(); release() }}>중단하고 오디오 참조 해제</button></div><p>{active ? '마이크 시험 중 · 최대 30초' : `${duration.toFixed(1)}초 / 최대 30초`}</p><StatusMessage>{status}</StatusMessage></div>
}
