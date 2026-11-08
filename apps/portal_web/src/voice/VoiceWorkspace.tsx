import { useState } from 'react'
import { Icon } from '../shared/components/Icon'
import { jsonPost, request, type VoiceStatus } from './api'
import { sampleSeconds } from './wav'
import { useObjectUrl, useRecorder } from './useRecorder'

export type Perform = (label: string, task: () => Promise<void>) => Promise<void>

type Props = {
  status: VoiceStatus
  busy: boolean
  locked: boolean
  perform: Perform
}

function Recording({ disabled, perform }: { disabled: boolean; perform: Perform }) {
  const recorder = useRecorder()
  const [consent, setConsent] = useState(false)
  const sampleUrl = useObjectUrl(recorder.sample)
  const capturing = recorder.mode !== 'idle'

  function enroll() {
    const sample = recorder.sample
    if (!consent || !sample) return
    void perform('목소리를 등록하고 있습니다.', async () => {
      await request('voice', {
        method: 'POST',
        headers: { 'Content-Type': 'audio/wav', 'X-Voice-Consent': 'yes' },
        body: sample,
      })
    })
  }

  return (
    <section className="voice-card" aria-labelledby="record-heading">
      <div className="card-heading"><span className="feature-icon"><Icon name="voice" /></span><h2 id="record-heading">보호자 목소리 등록</h2></div>
      <p className="card-copy">조용한 곳에서 평소 목소리로 10초 이상 말씀해 주세요. 목소리를 더 잘 담으려면 1~2분을 권장합니다.</p>
      <details className="reading-example"><summary>녹음할 때 읽을 예문</summary>
        <p>오늘은 함께 산책하던 길이 떠올랐어요. 바람이 불면 나뭇잎이 사각사각 소리를 냈지요. 다음에 같이 걸을 때도 이렇게 천천히 이야기를 나눠요.</p>
      </details>
      <label className="voice-consent"><input type="checkbox" checked={consent} disabled={disabled} onChange={event => {
        setConsent(event.target.checked)
        if (!event.target.checked) recorder.discard()
      }} /><span>제가 직접 말한 음성입니다. 녹음이 ElevenLabs로 전송되고, 제 목소리를 복제하여 입력한 문장을 읽는 데 동의합니다.</span></label>
      <div className="capture-area">
        <span className={'mic-indicator' + (recorder.mode === 'recording' ? ' is-recording' : '')}><Icon name="voice" size={22} /></span>
        <div><strong>{recorder.mode === 'requesting' ? '마이크 권한 확인 중' : recorder.mode === 'recording' ? '녹음 중' : recorder.sample ? '녹음 완료' : '녹음 대기'}</strong>
          <span className="time-readout">{clock(recorder.sample ? sampleSeconds(recorder.sample) : capturing ? recorder.seconds : 0)} / 02:00</span>
        </div>
        {capturing
          ? <button type="button" onClick={recorder.mode === 'requesting' ? recorder.discard : recorder.stop}>{recorder.mode === 'requesting' ? '취소' : '녹음 마치기'}</button>
          : <button type="button" className={recorder.sample ? '' : 'primary'} disabled={disabled || !consent} onClick={() => void recorder.start()}>{recorder.sample ? '다시 녹음' : '녹음 시작'}</button>}
      </div>
      {recorder.error && <p role="alert" className="error-copy">{recorder.error}</p>}
      {sampleUrl && <div className="sample-preview"><label>녹음한 목소리</label><audio controls src={sampleUrl} aria-label="녹음한 보호자 목소리 미리 듣기" />
        <button type="button" className="primary" disabled={disabled || !consent} onClick={enroll}>이 녹음으로 목소리 등록</button></div>}
    </section>
  )
}

function clock(seconds: number) {
  const whole = Math.max(0, Math.floor(seconds))
  return Math.floor(whole / 60).toString().padStart(2, '0') + ':' + (whole % 60).toString().padStart(2, '0')
}

const stateLabels = {
  creating: '등록 결과 확인 중',
  ready: '목소리 등록 완료',
  verification: 'ElevenLabs 본인 확인 필요',
  deleting: '삭제 결과 확인 중',
}

const stateDetails = {
  creating: '결과를 확인하는 동안 같은 녹음을 다시 전송하지 마세요.',
  ready: '등록한 보호자의 목소리로 여러 문장을 만들 수 있습니다. 다른 보호자의 녹음을 시작하려면 먼저 이 목소리를 삭제해 주세요.',
  verification: '연구 담당자가 ElevenLabs에서 본인 확인 절차를 마친 뒤 등록 상태를 다시 확인해 주세요.',
  deleting: 'ElevenLabs에서 삭제가 확인되기 전까지 새 목소리를 등록하거나 음성을 만들 수 없습니다.',
}

function Registered({ status, busy, locked, perform }: Props) {
  const [confirmDelete, setConfirmDelete] = useState(false)
  if (status.voice_state === 'empty') return null
  const state = status.voice_state
  function remove() {
    setConfirmDelete(false)
    void perform('등록한 목소리를 삭제하고 있습니다.', async () => { await request('voice', { method: 'DELETE', headers: { 'X-Voice-Reference': status.reference ?? '' } }) })
  }
  return (
    <section className="voice-card" aria-labelledby="record-heading">
      <div className="card-heading"><span className="feature-icon"><Icon name={state === 'ready' ? 'check' : 'voice'} /></span><h2 id="record-heading">{stateLabels[state]}</h2></div>
      <p className="card-copy">{stateDetails[state]}</p>
      {status.reference && <p className="voice-ref">목소리 참조 <code>{status.reference}</code></p>}
      <div className="voice-actions">
        {state !== 'ready' && <button type="button" disabled={busy} onClick={() => void perform('등록 상태를 확인하고 있습니다.', async () => {})}>상태 다시 확인</button>}
        {!confirmDelete && <button type="button" className="danger" disabled={busy || locked} onClick={() => setConfirmDelete(true)}>{state === 'deleting' ? '삭제 다시 시도' : '등록한 목소리 삭제'}</button>}
      </div>
      {confirmDelete && <div className="delete-confirm"><p>등록한 목소리를 ElevenLabs에서 삭제할까요? 이미 다운로드한 음성 파일은 별도로 보관됩니다.</p>
        <div className="voice-actions"><button type="button" onClick={() => setConfirmDelete(false)}>취소</button><button type="button" className="danger" disabled={busy || locked} onClick={remove}>삭제 확인</button></div>
      </div>}
    </section>
  )
}

function Speech({ status, busy, locked, perform }: Props) {
  const [text, setText] = useState('')
  const [result, setResult] = useState<{ audio: Blob; text: string } | null>(null)
  const url = useObjectUrl(result?.audio ?? null)
  const ready = status.voice_state === 'ready' && status.configured && !locked
  function generate() {
    if (!text.trim() || !ready) return
    void perform('입력한 문장의 음성을 만들고 있습니다.', async () => {
      setResult(null)
      const body = jsonPost({ text })
      const response = await request('speech', { ...body, headers: { ...body.headers, 'X-Voice-Reference': status.reference ?? '' } })
      const audio = await response.blob()
      if (!audio.size || !audio.type.toLowerCase().startsWith('audio/mpeg')) throw new Error('재생할 MP3를 받지 못했습니다. 다시 시도해 주세요.')
      setResult({ audio, text })
    })
  }
  return (
    <section className="voice-card" aria-labelledby="text-heading">
      <div className="card-heading"><span className="feature-icon"><Icon name="chat" /></span><h2 id="text-heading">문장을 음성으로</h2></div>
      <p className="card-copy">{status.voice_state === 'ready' ? '입력한 문장이 ElevenLabs로 전송됩니다. 환자 이름이나 등록번호는 입력하지 마세요.' : '목소리 등록을 마치면 원하는 문장을 입력하고 음성을 만들 수 있습니다.'}</p>
      <form onSubmit={event => { event.preventDefault(); generate() }}>
        <label className="speech-label" htmlFor="speech-text">읽을 문장</label>
        <textarea id="speech-text" rows={4} value={text} maxLength={1000} disabled={!ready || busy} placeholder="예: 오늘도 당신을 생각하고 있어요." onChange={event => { setText(event.target.value); setResult(null) }} />
        <div className="speech-actions"><span>{text.length} / 1,000자</span><button type="submit" className="primary" disabled={!ready || busy || !text.trim()}><Icon name="voice" size={17} />음성 만들기</button></div>
      </form>
      {ready && url && result && <div className="speech-output"><div className="output-heading"><strong>AI 합성 음성</strong><a href={url} download="favilium-message.mp3">MP3 다운로드</a></div>
        <p>{result.text}</p><audio controls src={url} aria-label="입력한 문장의 AI 합성 음성" /><small>환자에게 재생하기 전에 연구자가 먼저 들어보세요.</small>
      </div>}
    </section>
  )
}

export function VoiceWorkspace(props: Props) {
  const { status, busy, locked, perform } = props
  return <div className="voice-grid">
    {status.voice_state === 'empty' ? <Recording disabled={busy || locked || !status.configured} perform={perform} /> : <Registered {...props} />}
    <Speech key={status.reference ?? status.voice_state} {...props} />
  </div>
}
