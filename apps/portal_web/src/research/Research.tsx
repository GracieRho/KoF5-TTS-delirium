import { useEffect, useRef, useState, type FormEvent } from 'react'
import { WorkspaceShell } from '../shared/components/WorkspaceShell'
import { Icon } from '../shared/components/Icon'
import { useObjectUrl } from '../voice/useRecorder'
import './research.css'

type Voice = { reference: string; state: keyof typeof states; updated_at: string; consented_at: string | null; has_sample: boolean; speech_count: number }
type Message = { id: string; created_at: string; text_content: string }
type Scope = 'view' | 'manage'
type Mode = Scope | 'public' | 'checking'
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
  if (response.status === 401 && path !== 'session') window.dispatchEvent(new Event('research-session-ended'))
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
    {failed && <small role="alert">재생하지 못했습니다. 연구팀 링크를 다시 열어 주세요.</small>}</div>
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

function VoiceDetail({ voice, refresh, reload, saved, canManage }: { voice: Voice; refresh: number; reload: () => void; saved: () => void; canManage: boolean }) {
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
    {canManage && voice.state === 'ready' && voice.consented_at && <NewMessage base={base} saved={() => { setOffset(0); saved() }} />}
    <div className="section-row"><h3>합성한 안내 문장</h3><span>{voice.speech_count}건</span></div>
    {!result && <p role="status">안내 문장을 불러오는 중입니다.</p>}
    {result?.error && <p role="alert">{result.error}</p>}
    {result?.data && (result.data.items.length ? <ol className="research-messages">{result.data.items.map(item =>
      <li key={item.id}><time dateTime={item.created_at}>{when(item.created_at)}</time><p>{item.text_content}</p>
        <FilePlayer label={'안내 문장 ' + when(item.created_at)} path={base + '/speech/' + item.id} ext="MP3" /></li>)}</ol>
      : <p className="file-empty">보관된 합성 음성이 없습니다.</p>)}
    {result?.data && <Pager offset={offset} more={result.data.has_more} change={setOffset} />}
    </>}
    {canManage && <div className="research-delete">
      {confirm ? <div className="delete-confirm"><p>이 목소리를 ElevenLabs에서 삭제하고, 해당 원본 녹음·문장·합성 음성을 연구 보관함에서 모두 삭제할까요? 이미 내려받은 파일은 기기에 남습니다.</p>
        <div className="voice-actions"><button disabled={busy} onClick={() => setConfirm(false)}>취소</button><button className="danger" disabled={busy} onClick={() => void remove()}>{busy ? '삭제 중…' : '삭제 확인'}</button></div></div>
        : <button className="danger" onClick={() => setConfirm(true)}>목소리와 자료 삭제</button>}
      {error && <p role="alert" className="error-copy">{error}</p>}
    </div>}
  </section>
}

function Archive({ scope }: { scope: Scope }) {
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
      {voice ? <VoiceDetail key={voice.reference} voice={voice} canManage={scope === 'manage'} refresh={refresh} saved={reload} reload={() => { setSelected(''); setOffset(0); reload() }} /> :
        <section className="research-card detail-placeholder"><span className="feature-icon"><Icon name="voice" size={25} /></span><h2>확인할 목소리를 선택하세요</h2><p>선택한 목소리의 보관 동의, 원본 녹음과 합성 음성을 이곳에 표시합니다.</p></section>}
    </div></>
}

function PublicPreview() {
  return <>
    <div className="research-title"><div><h1>연구 음성 보관함</h1>
      <p>공개 미리보기입니다. 실제 연구 자료는 연구팀이 공유한 열람 또는 관리 링크에서 열립니다.</p></div></div>
    <div className="archive-grid">
      <section className="research-card">
        <div className="card-heading"><span className="feature-icon"><Icon name="memory" /></span><h2>등록한 목소리</h2></div>
        <div className="preview-entry"><span className="voice-state">예시</span><strong>보호자 목소리</strong></div>
      </section>
      <section className="research-card research-detail">
        <div className="card-heading"><span className="feature-icon"><Icon name="voice" /></span><h2>안내 문장 예시</h2></div>
        <blockquote className="example-speech">오늘도 당신을 생각하고 있어요. 오후에 다시 이야기해요.</blockquote>
        <p className="detail-meta">연구 보관함에서는 문장별 합성 음성과 보관에 동의한 원본 녹음을 들을 수 있습니다.</p>
      </section>
    </div>
  </>
}

function linkFromAddress() {
  return new URLSearchParams(window.location.hash.slice(1)).get('access')
}

export default function Research() {
  const [mode, setMode] = useState<Mode>(() => linkFromAddress() === null ? 'public' : 'checking')
  const [error, setError] = useState('')
  const revision = useRef(0)

  useEffect(() => {
    let mounted = true
    async function open(showProgress: boolean) {
      const id = ++revision.current
      const token = linkFromAddress()
      if (token === null) { setMode('public'); setError(''); return }
      if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
        setMode('public'); setError('연구팀이 공유한 링크 주소 전체를 열어 주세요.'); return
      }
      if (showProgress) setMode('checking')
      const current = () => mounted && id === revision.current && token === linkFromAddress()
      try {
        const response = await api('session', { method: 'POST', headers: { Authorization: 'Bearer ' + token } })
        const data = await response.json()
        if (data.scope !== 'view' && data.scope !== 'manage') throw new Error('연구팀 링크의 권한을 확인할 수 없습니다.')
        if (current()) { setMode(data.scope); setError('') }
      } catch (reason) {
        if (current()) { setMode('public'); setError(errorText(reason)) }
      }
    }
    const enter = () => { void open(true) }
    const renew = () => { void open(false) }
    enter()
    window.addEventListener('hashchange', enter)
    window.addEventListener('research-session-ended', enter)
    window.addEventListener('focus', renew)
    const timer = window.setInterval(renew, 45 * 60 * 1000)
    return () => {
      mounted = false
      window.clearInterval(timer)
      window.removeEventListener('hashchange', enter)
      window.removeEventListener('research-session-ended', enter)
      window.removeEventListener('focus', renew)
    }
  }, [])

  async function close() {
    try {
      await api('logout', { method: 'POST' })
      revision.current++
      window.history.replaceState(null, '', window.location.pathname)
      setMode('public'); setError('')
    } catch (reason) { setError(errorText(reason)) }
  }
  const live = mode === 'view' || mode === 'manage'
  const actions = live ? <div className="research-access"><span>{mode === 'manage' ? '연구팀 관리' : '연구팀 열람'}</span>
    <button onClick={() => void close()}>보관함 나가기</button></div> : <span>공개 미리보기</span>
  return <WorkspaceShell research actions={mode === 'checking' ? undefined : actions}>
    {error && <p className="notice error-notice" role="alert">{error}</p>}
    {live ? <Archive key={mode} scope={mode} /> : mode === 'checking' ? <p role="status">연구 음성 보관함을 여는 중입니다.</p> : <PublicPreview />}
  </WorkspaceShell>
}
