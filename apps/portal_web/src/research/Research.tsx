import { useEffect, useRef, useState, type FormEvent } from 'react'
import { WorkspaceShell } from '../shared/components/WorkspaceShell'
import { Icon } from '../shared/components/Icon'
import { VoiceWave } from '../family/components/VoiceWave'
import { useObjectUrl } from '../voice/useRecorder'
import './research.css'

type Voice = { reference: string; state: keyof typeof states; updated_at: string; consented_at: string | null; has_sample: boolean; speech_count: number }
type Message = { id: string; created_at: string; text_content: string }
type Page<T> = { items: T[]; has_more: boolean }
const states = { ready: '등록 완료', verification: '본인 확인 필요', creating: '등록 확인 중', deleting: '삭제 확인 중' }
const pageSize = 20
const date = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Seoul' })
const when = (timestamp: string) => date.format(new Date(timestamp))
const root = '/api/research/'
const errorText = (error: unknown) => error instanceof Error ? error.message : '요청을 완료하지 못했습니다.'

async function api(path: string, options: RequestInit = {}) {
  const response = await fetch(root + path, { ...options, cache: 'no-store', credentials: 'same-origin' })
  if (response.ok) return response
  if (response.status === 401 && !path.startsWith('login/')) window.dispatchEvent(new Event('research-session-ended'))
  const data = await response.json().catch(() => ({}))
  throw new Error(typeof data.detail === 'string' ? data.detail : '자료를 불러오지 못했습니다. 다시 시도해 주세요.')
}

function usePage<T>(path: string, refresh: number, enabled = true) {
  const [result, setResult] = useState<{ path: string; data?: Page<T>; error?: string } | null>(null)
  useEffect(() => {
    if (!enabled) return
    const cancel = new AbortController()
    api(path, { signal: cancel.signal }).then(r => r.json()).then(data => {
      if (!cancel.signal.aborted) setResult({ path, data })
    }).catch(reason => { if (!cancel.signal.aborted) setResult({ path, error: errorText(reason) }) })
    return () => cancel.abort()
  }, [path, refresh, enabled])
  return enabled && result?.path === path ? result : null
}

function Pager({ offset, more, change }: { offset: number; more: boolean; change: (offset: number) => void }) {
  if (!offset && !more) return null
  return <nav className="research-pager" aria-label="페이지 이동"><button disabled={!offset} onClick={() => change(Math.max(0, offset - pageSize))}>이전</button>
    <span>{Math.floor(offset / pageSize) + 1}쪽</span><button disabled={!more} onClick={() => change(offset + pageSize)}>다음</button></nav>
}

function FilePlayer({ path, label, ext }: { path: string; label: string; ext: string }) {
  const [failed, setFailed] = useState(false)
  const url = root + path
  return <div className="research-player"><audio aria-label={label} controls preload="none" src={url} onError={() => setFailed(true)} />
    <a href={url + '?download=true'} download aria-label={label + ' ' + ext + ' 다운로드'}>{ext} 다운로드</a>
    {failed && <small role="alert">재생하지 못했습니다. 로그인 상태를 확인하고 다시 열어 주세요.</small>}</div>
}

function NewMessage({ base, saved }: { base: string; saved: () => void }) {
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const [recovery, setRecovery] = useState<Blob | null>(null)
  const url = useObjectUrl(recovery)
  async function create(event: FormEvent) {
    event.preventDefault()
    if (busy || !text.trim()) return
    setBusy(true); setNotice(''); setRecovery(null)
    try {
      const response = await api(base + '/speech', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }) })
      if (response.headers.get('X-Favilium-Archive') === 'saved') {
        setNotice('새 합성음을 보관했습니다. 아래 목록에서 들어보세요.'); setText(''); saved()
      } else {
        setRecovery(await response.blob()); setNotice('연구 서버에 보관했는지 확인할 수 없습니다. 생성된 MP3를 내려받고 목록을 확인해 주세요.')
      }
    } catch (reason) { setNotice(errorText(reason)) }
    finally { setBusy(false) }
  }
  return <details className="reading-example research-compose"><summary>이 목소리로 새 안내 문장 만들기</summary>
    <form onSubmit={create}><label htmlFor="new-guidance">읽을 안내 문장</label>
      <textarea id="new-guidance" rows={3} maxLength={1000} disabled={busy} value={text} onChange={e => setText(e.target.value)} />
      <p>문장이 ElevenLabs로 전송됩니다. 환자 이름과 등록번호는 입력하지 마세요.</p>
      <button type="submit" className="primary" disabled={busy || !text.trim()}>{busy ? '합성 중…' : '음성 만들기'}</button></form>
      {notice && <p role="status">{notice}</p>}
      {url && <div className="research-player"><audio controls src={url} aria-label="방금 합성한 안내 문장" /><a href={url} download="favilium-message.mp3">MP3 다운로드</a></div>}
    </details>
}

function VoiceDetail({ voice, refresh, reload, saved }: { voice: Voice; refresh: number; reload: () => void; saved: () => void }) {
  const [offset, setOffset] = useState(0)
  const [confirm, setConfirm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const base = 'voices/' + encodeURIComponent(voice.reference)
  const deleting = voice.state === 'deleting'
  const result = usePage<Message>(base + '/speech?offset=' + offset, refresh, !deleting)
  async function remove() {
    setBusy(true)
    try { await api(base, { method: 'DELETE' }); reload() }
    catch (reason) { setError(errorText(reason)) }
    finally { setBusy(false) }
  }
  return <section className="research-card research-detail" aria-labelledby="detail-title">
    <div className="card-heading"><span className="feature-icon"><Icon name="voice" /></span><div><h2 id="detail-title">목소리 상세</h2><code>{voice.reference}</code></div></div>
    <p className="detail-meta">{voice.consented_at ? '연구 보관 동의 · ' + when(voice.consented_at) : '연구 자료 보관 동의 기록 없음'}</p>
    {deleting ? <p className="notice">삭제 결과를 확인하고 있습니다. 자료 열람이 중지되었습니다.</p> : <>
    <h3>보호자 원본 녹음</h3>
    {voice.has_sample ? <FilePlayer label="보호자 원본 녹음" path={base + '/sample'} ext="WAV" /> : <p className="file-empty">보관된 원본 녹음이 없습니다.</p>}
    {voice.state === 'ready' && voice.consented_at && <NewMessage base={base} saved={() => { setOffset(0); saved() }} />}
    <div className="section-row"><h3>합성한 안내 문장</h3><span>{voice.speech_count}건</span></div>
    {!result && <p role="status">안내 문장을 불러오는 중입니다.</p>}
    {result?.error && <p role="alert">{result.error}</p>}
    {result?.data && (result.data.items.length ? <ol className="research-messages">{result.data.items.map(item =>
      <li key={item.id}><time dateTime={item.created_at}>{when(item.created_at)}</time><p>{item.text_content}</p>
        <FilePlayer label={'안내 문장 ' + when(item.created_at)} path={base + '/speech/' + item.id} ext="MP3" /></li>)}</ol>
      : <p className="file-empty">보관된 합성 음성이 없습니다.</p>)}
    {result?.data && <Pager offset={offset} more={result.data.has_more} change={setOffset} />}
    </>}
    <div className="research-delete">
      {confirm ? <div className="delete-confirm"><p>이 목소리를 ElevenLabs에서 삭제하고, 해당 원본 녹음·문장·합성 음성을 연구 보관함에서 모두 삭제할까요? 이미 내려받은 파일은 기기에 남습니다.</p>
        <div className="voice-actions"><button disabled={busy} onClick={() => setConfirm(false)}>취소</button><button className="danger" disabled={busy} onClick={() => void remove()}>{busy ? '삭제 중…' : '삭제 확인'}</button></div></div>
        : <button className="danger" onClick={() => setConfirm(true)}>목소리와 자료 삭제</button>}
      {error && <p role="alert" className="error-copy">{error}</p>}
    </div>
  </section>
}

function Archive() {
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('')
  const [offset, setOffset] = useState(0)
  const [selected, setSelected] = useState('')
  const [refresh, setRefresh] = useState(0)
  const result = usePage<Voice>('voices?offset=' + offset + '&search=' + encodeURIComponent(filter), refresh)
  const rows = result?.data?.items ?? []
  const voice = rows.find(item => item.reference === selected)
  function find(event: FormEvent) {
    event.preventDefault()
    setFilter(search.trim().toLowerCase()); setOffset(0); setSelected('')
  }
  function reload() { setRefresh(n => n + 1) }
  return <>
    <div className="research-title"><div><h1>연구 음성 보관함</h1><p>목소리 참조 번호로 보호자의 원본 녹음과 합성한 안내 문장을 확인하세요.</p></div>
      <button onClick={reload}>새로고침</button></div>
    <div className="archive-grid">
      <section className="research-card research-list"><div className="card-heading"><span className="feature-icon"><Icon name="memory" /></span><h2>등록한 목소리</h2></div>
        <form className="research-search" onSubmit={find}><label htmlFor="reference-search">목소리 참조 번호 검색</label><div>
          <input id="reference-search" placeholder="참조 번호 전체 또는 일부" value={search} maxLength={24} pattern="[0-9a-fA-F]*" title="숫자와 영문 A~F로 입력해 주세요." onChange={e => setSearch(e.target.value)} />
          <button type="submit">검색</button></div></form>
        {filter && <button className="clear-filter" onClick={() => { setSearch(''); setFilter(''); setOffset(0); setSelected('') }}>검색 해제</button>}
        {!result && <p role="status">목소리 목록을 불러오는 중입니다.</p>}
        {result?.error && <p className="error-copy" role="alert">{result.error}</p>}
        {result?.data && (!rows.length ? <p className="file-empty">{filter ? '검색 결과가 없습니다.' : '등록한 목소리가 없습니다.'}</p> :
          <ul className="voice-index">{rows.map(item =>
            <li key={item.reference}><button aria-pressed={selected === item.reference} onClick={() => setSelected(item.reference)}>
              <span className="voice-index-head"><span className="voice-state">{states[item.state]}</span><span>합성음 {item.speech_count}건</span></span>
              <code>{item.reference}</code><small>상태 변경 · {when(item.updated_at)}</small></button></li>)}</ul>)}
        {result?.data && <Pager offset={offset} more={result.data.has_more} change={n => { setOffset(n); setSelected('') }} />}
      </section>
      {voice ? <VoiceDetail key={voice.reference} voice={voice} refresh={refresh} saved={reload} reload={() => { setSelected(''); setOffset(0); reload() }} /> :
        <section className="research-card detail-placeholder"><span className="feature-icon"><Icon name="voice" size={25} /></span><h2>확인할 목소리를 선택하세요</h2><p>선택한 목소리의 보관 동의, 원본 녹음과 합성 음성을 이곳에 표시합니다.</p></section>}
    </div></>
}

function Login({ onLogin }: { onLogin: (email: string) => void }) {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [proof, setProof] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError('')
    try {
      const headers = { 'Content-Type': 'application/json' }
      if (!sent) {
        await api('login/email', { method: 'POST', headers, body: JSON.stringify({ email }) })
        setSent(true)
      } else {
        const response = await api('login/verify', { method: 'POST', headers, body: JSON.stringify({ email, proof }) })
        onLogin((await response.json()).email)
      }
    } catch (reason) { setError(errorText(reason)) }
    finally { setBusy(false) }
  }
  return <div className="research-entry">
    <section className="welcome-band research-welcome"><div><h1>연구 음성 보관함</h1><p>보호자의 목소리와 그 목소리로 만든<br />안내 문장을 한곳에서 확인합니다.</p></div><VoiceWave /></section>
    <section className="research-card login-card"><div className="card-heading"><span className="feature-icon"><Icon name="shield" /></span><h2>연구자 로그인</h2></div>
      <p className="card-copy">{sent ? '인증 메일을 보냈습니다. 메일 버튼을 길게 누르거나 마우스 오른쪽 버튼으로 링크 주소를 복사해 아래에 붙여넣으세요. 숫자 코드가 있다면 코드만 입력해도 됩니다.' : '연구팀에 등록한 이메일로 일회용 인증 메일을 받으세요.'}</p>
      <form onSubmit={submit}><label htmlFor="research-email">연구자 이메일</label><input id="research-email" type="email" autoComplete="email" required disabled={sent || busy} value={email} onChange={e => setEmail(e.target.value)} />
        {sent && <><label htmlFor="research-proof">메일의 링크 주소 또는 인증 코드</label><input id="research-proof" type="password" autoComplete="one-time-code" required value={proof} onChange={e => setProof(e.target.value)} /></>}
        {error && <p className="error-copy" role="alert">{error}</p>}
        <button type="submit" className="primary" disabled={busy}>{busy ? '확인 중…' : sent ? '로그인' : '인증 메일 받기'}</button></form>
      {sent && <button className="resend" disabled={busy} onClick={() => { setSent(false); setProof(''); setError('') }}>이메일 재입력 · 다시 받기</button>}
      <a href="/studio" className="research-studio-link">보호자 녹음실 열기 <Icon name="arrow" size={15} /></a>
    </section></div>
}

export default function Research() {
  const [email, setEmail] = useState('')
  const [checking, setChecking] = useState(true)
  const authRevision = useRef(0)
  const [error, setError] = useState('')
  useEffect(() => {
    let active = true
    const end = () => { if (active) { authRevision.current++; setEmail('') } }
    const check = async () => {
      const revision = ++authRevision.current
      const current = () => active && revision === authRevision.current
      try {
        const response = await fetch(root + 'session', { credentials: 'same-origin', cache: 'no-store' })
        if (!current()) return
        if (response.status === 401) { setEmail(''); setError(''); return }
        if (!response.ok) throw new Error('연구자 로그인 상태를 확인할 수 없습니다.')
        const user = await response.json()
        if (current()) { setEmail(user.email); setError('') }
      } catch (reason) { if (current()) { setEmail(''); setError(errorText(reason)) } }
      finally { if (current()) setChecking(false) }
    }
    void check()
    window.addEventListener('research-session-ended', end)
    window.addEventListener('focus', check)
    const timer = window.setInterval(check, 60000)
    return () => { active = false; window.clearInterval(timer); window.removeEventListener('research-session-ended', end); window.removeEventListener('focus', check) }
  }, [])
  async function logout() {
    try { await api('logout', { method: 'POST' }); authRevision.current++; setEmail(''); setError('') }
    catch (reason) { setError(errorText(reason)) }
  }
  return <WorkspaceShell research actions={email && <button onClick={() => void logout()}>로그아웃</button>}>
    {error && <p className="notice error-notice" role="alert">{error}</p>}
    {checking ? <p role="status">로그인 상태 확인 중…</p> : email ? <Archive /> : <Login onLogin={identity => { authRevision.current++; setEmail(identity); setError('') }} />}
  </WorkspaceShell>
}
