import { useEffect, useRef, useState } from 'react'
import { VoiceWave } from './family/components/VoiceWave'
import { WorkspaceShell } from './shared/components/WorkspaceShell'
import { VoiceWorkspace, type Perform } from './voice/VoiceWorkspace'
import { openWorkspace, type VoiceStatus } from './voice/api'

const localWorkspace: VoiceStatus = { configured: false, voice_state: 'empty' }

export function App() {
  const [status, setStatus] = useState<VoiceStatus | null>(null)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [known, setKnown] = useState(false)
  const active = useRef(false)
  const revision = useRef(0)
  const reading = useRef<Promise<VoiceStatus> | null>(null)

  useEffect(() => {
    function refresh() {
      if (active.current) return
      const latest = ++revision.current
      const check = openWorkspace()
      reading.current = check
      void check.then(next => {
        if (latest === revision.current) {
          setStatus(next)
          setKnown(true)
          setError('')
        }
      }).catch(reason => {
        if (latest === revision.current) {
          setKnown(false)
          setError(reason.message)
        }
      }).finally(() => {
        if (reading.current === check) reading.current = null
      })
    }
    refresh()
    window.addEventListener('focus', refresh)
    return () => { revision.current++; window.removeEventListener('focus', refresh) }
  }, [])

  const perform: Perform = async (label, task) => {
    if (active.current) return
    const latest = ++revision.current
    active.current = true
    setBusy(label)
    setError('')
    let actionError = ''
    try {
      // Finish an older read before a write. Its result cannot replace the post-write state.
      await reading.current?.catch(() => {})
      if (latest !== revision.current) return
      await task()
    } catch (reason) {
      actionError = reason instanceof Error ? reason.message : '요청을 처리하지 못했습니다.'
    }
    try {
      if (latest !== revision.current) return
      const next = await openWorkspace()
      if (latest !== revision.current) return
      setStatus(next)
      setKnown(true)
    } catch (reason) {
      if (latest !== revision.current) return
      setKnown(false)
      actionError = [actionError, reason instanceof Error ? reason.message : '현재 상태를 확인할 수 없습니다.'].filter(Boolean).join(' ')
    } finally {
      active.current = false
      if (latest === revision.current) {
        setBusy('')
        setError(actionError)
      }
    }
  }

  const check = () => void perform('현재 상태를 확인하고 있습니다.', async () => {})

  return (
    <WorkspaceShell>
      <section className="welcome-band voice-hero">
        <div><h1>익숙한 목소리로<br />전하는 한마디</h1>
          <p>보호자의 목소리를 녹음하고,<br />입력한 문장을 그 목소리로 들어보세요.</p>
        </div>
        <VoiceWave />
      </section>
      <div className="feedback" aria-live="polite" aria-atomic="true">{busy}</div>
      {error && <div className="notice error-notice" role="alert"><span>{error}</span>{!known && <button disabled={!!busy} onClick={check}>상태 다시 확인</button>}</div>}
      {known && !status?.configured && <p className="notice">음성 서비스 연결을 기다리고 있습니다. {status?.voice_state === 'empty' ? '지금은 녹음과 미리 듣기를 사용할 수 있습니다.' : '연결 후 등록한 목소리로 문장을 만들거나 목소리를 삭제할 수 있습니다.'}</p>}
      <VoiceWorkspace status={status ?? localWorkspace} busy={!!busy} locked={!known} perform={perform} />
    </WorkspaceShell>
  )
}
