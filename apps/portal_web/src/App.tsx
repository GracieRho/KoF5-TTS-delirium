import { useEffect, useRef, useState } from 'react'
import { VoiceWave } from './family/components/VoiceWave'
import { WorkspaceShell } from './shared/components/WorkspaceShell'
import { Icon } from './shared/components/Icon'
import { VoiceWorkspace, type Perform } from './voice/VoiceWorkspace'
import { jsonPost, readStatus, request, type VoiceStatus } from './voice/api'

export function App() {
  const [status, setStatus] = useState<VoiceStatus | null>(null)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [known, setKnown] = useState(false)
  const active = useRef(false)
  const revision = useRef(0)

  useEffect(() => {
    let alive = true
    function refresh() {
      if (active.current) return
      const revisionAtStart = ++revision.current
      const current = () => alive && !active.current && revision.current === revisionAtStart
      void readStatus().then(next => {
        if (current()) { setStatus(next); setKnown(true); setError('') }
      }).catch(reason => {
        if (current()) { setKnown(false); setError(reason.message) }
      })
    }
    refresh()
    window.addEventListener('focus', refresh)
    return () => { alive = false; window.removeEventListener('focus', refresh) }
  }, [])

  const perform: Perform = async (label, task) => {
    if (active.current) return
    active.current = true
    revision.current++
    setBusy(label)
    setError('')
    let actionError = ''
    try {
      await task()
    } catch (reason) {
      actionError = reason instanceof Error ? reason.message : '요청을 처리하지 못했습니다.'
    }
    try {
      setStatus(await readStatus())
      setKnown(true)
    } catch {
      setKnown(false)
      actionError += (actionError ? ' ' : '') + '현재 상태를 확인할 수 없습니다. 연결을 확인한 뒤 다시 확인해 주세요.'
    } finally {
      active.current = false
      setBusy('')
      setError(actionError)
    }
  }

  const authenticated = status?.authenticated === true
  const check = () => void perform('현재 상태를 확인하고 있습니다.', async () => {})
  const login = () => void perform('접속 코드를 확인하고 있습니다.', async () => {
    await request('login', jsonPost({ code }))
    setCode('')
  })

  return (
    <WorkspaceShell actions={authenticated && <button className="signout" type="button" disabled={!!busy}
      onClick={() => void perform('로그아웃하고 있습니다.', async () => {
        setStatus(null)
        await request('logout', { method: 'POST' })
      })}>로그아웃</button>}>
      <section className="welcome-band voice-hero">
        <div><h1>익숙한 목소리로<br />전하는 한마디</h1>
          <p>보호자의 목소리를 녹음하고,<br />입력한 문장을 그 목소리로 들어보세요.</p>
        </div>
        <VoiceWave />
      </section>
      <div className="feedback" aria-live="polite" aria-atomic="true">{busy}</div>
      {error && <div className="notice error-notice" role="alert"><span>{error}</span>{!known && <button disabled={!!busy} onClick={check}>상태 다시 확인</button>}</div>}
      {!status && !error && <p className="loading-note">연결 상태를 확인하고 있습니다.</p>}
      {status && !authenticated && <section className="voice-card access-card">
        <div className="card-heading"><span className="feature-icon"><Icon name="shield" /></span><h2>연구자 접속</h2></div>
        <p className="card-copy">연구팀에서 받은 접속 코드로 음성 작업실을 열어주세요.</p>
        <form onSubmit={event => { event.preventDefault(); login() }}>
          <label className="speech-label" htmlFor="access-code">접속 코드</label>
          <div className="login-row"><input id="access-code" type="password" autoComplete="current-password" required maxLength={512} value={code} onChange={event => setCode(event.target.value)} />
            <button type="submit" className="primary" disabled={!code.trim() || !!busy || !known}>작업실 열기<Icon name="arrow" size={16} /></button></div>
        </form>
      </section>}
      {authenticated && status && <>
        {!status.configured && <p className="notice">음성 서비스가 준비되지 않았습니다. 연구 담당자가 서버 연결 설정을 확인한 뒤 다시 접속해 주세요.</p>}
        <VoiceWorkspace status={status} busy={!!busy} locked={!known} perform={perform} />
      </>}
    </WorkspaceShell>
  )
}
