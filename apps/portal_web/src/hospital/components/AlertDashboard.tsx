import { useCallback, useEffect, useRef, useState } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import { RequestEpoch } from '../../shared/hooks/requestEpoch'
import { UUID } from '../../shared/types/constants'
import type { Patient, SyntheticAlert } from '../../shared/types/domain'
import { EmptyState } from '../../shared/components/EmptyState'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'
import { formatHospitalTime } from '../utils/format'

const stateLabel = { created: '경고 생성 · 포털 표시 미확인', delivered: '합성 포털 표시 · 의료진 확인 전', acknowledged: '담당 직원 명시 확인', resolved: '담당 직원 후속 조치 완료 표시', failed: '보조 경고 실패' }
const riskLabel: Record<string, string> = { breathing: '호흡 곤란', chest_pain: '흉통', fall: '낙상', pain: '통증', dizziness: '어지러움', distress: '도움 요청' }
const action = { created: ['synthetic_alert_dashboard_receipt','delivered','합성 포털 표시 기록'], delivered: ['synthetic_alert_ack','acknowledged','직원 확인 기록'], acknowledged: ['synthetic_alert_resolve','resolved','후속 조치 완료 기록'] } as const

export function AlertDashboard({ api, token, patient }: { api: SupabaseRest; token: string; patient: Patient }) {
  const requests = useRef(new RequestEpoch()); const [rows, setRows] = useState<SyntheticAlert[]>([]); const [status, setStatus] = useState(''); const [busy, setBusy] = useState(false)
  const refresh = useCallback(async () => {
    if (!patient.encounter_id) return null
    const owner = requests.current.begin(); setBusy(true); setRows([])
    try {
      const ready = await hospitalApi.rpc<Array<{ patient_id: string; ready: boolean }>>(api, token, 'synthetic_alert_staff_ready')
      if (!requests.current.owns(owner) || ready.length !== 1 || ready[0].ready !== true || ready[0].patient_id !== patient.patient_id) return null
      const list = await hospitalApi.rpc<SyntheticAlert[]>(api, token, 'synthetic_alert_staff_list')
      if (!requests.current.owns(owner)) return null
      const scoped = list.filter(row => row.patient_id === patient.patient_id && row.encounter_id === patient.encounter_id && UUID.test(row.alert_id) && row.state in stateLabel).slice(0, 20)
      setRows(scoped); setStatus(`이번 입원의 합성 보조 경고 ${scoped.length}건을 조회했습니다. 생성·표시·직원 확인은 각각 다른 상태입니다.`); return scoped
    } catch { if (requests.current.owns(owner)) setStatus('합성 경고를 읽지 못했습니다.'); return null }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }, [api, token, patient])
  useEffect(() => { requests.current.invalidate(); setRows([]); void refresh(); return () => requests.current.invalidate() }, [refresh])
  async function transition(alert: SyntheticAlert) {
    const next = action[alert.state as keyof typeof action]; if (!next || !patient.encounter_id) return
    const owner = requests.current.begin(); setBusy(true)
    try { const result = await hospitalApi.rpc<Array<{ authorized: boolean; alert_id: string; state: string }>>(api, token, next[0], { p_alert_id: alert.alert_id }); if (!requests.current.owns(owner) || result.length !== 1 || result[0].authorized !== true || result[0].alert_id !== alert.alert_id || result[0].state !== next[1]) throw new Error('unconfirmed transition'); setBusy(false); const latest = await refresh(); if (!latest?.some(row => row.alert_id === alert.alert_id && row.state === next[1])) throw new Error('transition not persisted'); setStatus(`${stateLabel[next[1]]} 상태를 DB에서 다시 확인했습니다. 실제 임상 전달을 뜻하지 않습니다.`) }
    catch { if (requests.current.owns(owner)) { setRows([]); setStatus('경고 상태 변경 결과를 확인하지 못했습니다. 환자를 다시 선택하세요.') } }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }
  async function sweep() {
    const owner = requests.current.begin(); setBusy(true)
    try { const result = await hospitalApi.rpc<Array<{ authorized: boolean; failed_count: number }>>(api, token, 'synthetic_alert_timeout_sweep'); if (!requests.current.owns(owner) || result.length !== 1 || result[0].authorized !== true || !Number.isInteger(result[0].failed_count) || result[0].failed_count < 0) throw new Error('unconfirmed sweep'); setBusy(false); const latest = await refresh(); if (!latest) throw new Error('sweep not reloaded'); setStatus(`명시적으로 시간 초과 ${result[0].failed_count}건을 판정하고 현재 입원 상태를 다시 읽었습니다. 자동 임상 전달은 아닙니다.`) }
    catch { if (requests.current.owns(owner)) setStatus('시간 초과 판정 결과를 확인하지 못했습니다.') }
    finally { if (requests.current.owns(owner)) setBusy(false) }
  }
  return <div><div className="button-row"><button disabled={busy} onClick={() => void refresh()}>경고 새로고침</button><button disabled={busy} onClick={() => void sweep()}>시간 초과 판정 새로고침</button></div>{!rows.length ? <EmptyState>이번 입원에 표시할 합성 보조 경고가 없습니다.</EmptyState> : <ul className="item-list">{rows.map(alert => { const next = action[alert.state as keyof typeof action]; return <li className="item warning-strip" key={alert.alert_id}><div className="item-title">{riskLabel[alert.risk_category] ?? '위험 발화 후보'} · {stateLabel[alert.state]}</div><p>{alert.state === 'failed' ? '보조 경고 실패 상태입니다.' : '기존 의료진 호출 수단을 대체하지 않습니다.'}</p><div className="item-meta">생성 {formatHospitalTime(alert.created_at)}{alert.acknowledged_at ? ` · 직원 확인 ${formatHospitalTime(alert.acknowledged_at)}` : ''}</div>{next && <button disabled={busy} onClick={() => void transition(alert)}>{next[2]}</button>}</li> })}</ul>}<StatusMessage tone={rows.length ? 'warning' : 'info'}>{status}</StatusMessage></div>
}
