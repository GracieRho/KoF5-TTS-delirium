import { useState } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'

export function AlertDashboard({ api, token }: { api: SupabaseRest; token: string }) {
  const [count, setCount] = useState<number | null>(null); const [status, setStatus] = useState(''); const [busy, setBusy] = useState(false)
  async function refresh() { setBusy(true); try { const rows = await hospitalApi.rpc<unknown[]>(api, token, 'synthetic_alert_staff_list'); setCount(rows.length); setStatus('합성 보조 경고 목록을 갱신했습니다. 표시가 임상 전달이나 확인을 뜻하지 않습니다.') } catch { setStatus('합성 경고를 읽지 못했습니다.') } finally { setBusy(false) } }
  async function sweep() { setBusy(true); try { await hospitalApi.rpc(api, token, 'synthetic_alert_timeout_sweep'); await refresh(); setStatus('시간 초과를 명시적으로 판정했습니다. 자동 임상 경고는 아닙니다.') } catch { setStatus('시간 초과 판정 결과를 확인하지 못했습니다.') } finally { setBusy(false) } }
  return <div><div className="button-row"><button disabled={busy} onClick={() => void refresh()}>경고 새로고침</button><button disabled={busy} onClick={() => void sweep()}>시간 초과 판정 새로고침</button></div>{count !== null && <p><strong>{count}건</strong>의 합성 보조 경고가 있습니다.</p>}<StatusMessage tone={count ? 'warning' : 'info'}>{status}</StatusMessage></div>
}
