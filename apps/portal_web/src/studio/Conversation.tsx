import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Icon } from '../shared/components/Icon'
import { wavBase64 } from '../guardian/utils/voiceAudio'
import { useRecorder } from './useRecorder'
import { studioRequest, type StudioState, type TurnResult } from './api'

type Message = { question: string; reply: string; url: string; count: number }
export function Conversation({
  state,
  report
}: {
  state: StudioState
  report: (message: string) => void
}) {
  const [text, setText] = useState('')
  const [consent, setConsent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<Message | null>(null)
  const [starting, setStarting] = useState(false)
  const audio = useRef<HTMLAudioElement>(null)
  const mounted = useRef(true)
  const inFlight = useRef(false)
  const epoch = useRef(0)
  const recorder = useRecorder()
  const hasMemory = state.memories.some((m) => m.category !== 'avoid')
  const ready =
    state.voice.status === 'created' &&
    state.providers.conversation &&
    state.providers.voice &&
    hasMemory
  useEffect(
    () => () => {
      mounted.current = false
      epoch.current++
    },
    []
  )
  useEffect(() => {
    mounted.current = true
  }, [])
  useEffect(() => {
    if (!message) return
    return () => URL.revokeObjectURL(message.url)
  }, [message])
  useEffect(() => {
    if (!ready) {
      epoch.current++
      audio.current?.pause()
      setMessage(null)
    }
  }, [ready])
  function revoke() {
    epoch.current++
    recorder.cancel()
    audio.current?.pause()
    setMessage(null)
    setText('')
    setConsent(false)
  }
  async function submit(event?: FormEvent) {
    event?.preventDefault()
    if (!ready || !consent || !text.trim() || inFlight.current) return
    inFlight.current = true
    const owner = ++epoch.current
    setBusy(true)
    audio.current?.pause()
    try {
      const response = await studioRequest<TurnResult>('/turn', 'POST', {
        text,
        provider_processing_consent: true
      })
      if (!mounted.current || epoch.current !== owner) return
      const bytes = Uint8Array.from(atob(response.audio_base64), (c) => c.charCodeAt(0))
      setMessage({
        question: text,
        reply: response.reply,
        url: URL.createObjectURL(new Blob([bytes.buffer], { type: 'audio/mpeg' })),
        count: response.memory_count
      })
      setText('')
    } catch (error) {
      if (mounted.current && epoch.current === owner)
        report(error instanceof Error ? error.message : '대화에 실패했습니다.')
    } finally {
      inFlight.current = false
      if (mounted.current) setBusy(false)
    }
  }
  async function start() {
    if (inFlight.current) return
    audio.current?.pause()
    setStarting(true)
    try {
      await recorder.start()
    } catch {
      report('마이크를 사용할 수 없습니다. 질문을 직접 입력해주세요.')
    } finally {
      if (mounted.current) setStarting(false)
    }
  }
  async function transcribe() {
    const wav = recorder.stop()
    if (!wav || inFlight.current) return
    inFlight.current = true
    const owner = ++epoch.current
    setBusy(true)
    try {
      const response = await studioRequest<{ text: string }>('/transcribe', 'POST', {
        wav_base64: wavBase64(wav),
        provider_processing_consent: true
      })
      if (mounted.current && epoch.current === owner) setText(response.text)
    } catch (error) {
      if (mounted.current && epoch.current === owner)
        report(error instanceof Error ? error.message : '전사하지 못했습니다.')
    } finally {
      wav.fill(0)
      inFlight.current = false
      if (mounted.current) setBusy(false)
    }
  }
  useEffect(() => {
    const hide = () => {
      if (document.hidden) {
        epoch.current++
        audio.current?.pause()
        setMessage(null)
      }
    }
    document.addEventListener('visibilitychange', hide)
    return () => document.removeEventListener('visibilitychange', hide)
  }, [])
  return (
    <section>
      <div className="section-heading">
        <div>
          <h1>목소리로 대화하기</h1>
          <p className="compact">등록한 기억을 바탕으로, 익숙한 목소리로 답합니다.</p>
        </div>
        <span className="state-label">{ready ? '대화 준비 완료' : '등록 후 사용할 수 있어요'}</span>
      </div>
      <div className="conversation-panel">
        <div className="conversation-intro">
          <div className="voice-symbol">
            <Icon name="chat" size={32} />
          </div>
          <h2>
            {state.profile.guardian_name
              ? `${state.profile.guardian_name}님의 목소리와 함께`
              : '우리 가족의 이야기를 나눠요'}
          </h2>
          <p>
            가족이 남긴 기억을 AI가 읽어주는 시연입니다.
            <br />
            실제 보호자와 연결된 통화가 아닙니다.
          </p>
        </div>
        {message && (
          <div className="conversation-result">
            <div className="question-bubble">{message.question}</div>
            <div className="reply-bubble">
              <span className="memory-category">가족 목소리로 읽는 AI 답변</span>
              <p>{message.reply}</p>
              <audio ref={audio} controls src={message.url} aria-label="복제 목소리로 답변 듣기" />
              <small>
                일반 기억 {message.count}건을 문맥으로 전달 · 대화 원문은 서버에 저장하지 않음
              </small>
            </div>
          </div>
        )}
        {!ready && (
          <p className="blocking-note">
            가족 소개, 일반 기억 한 건, 복제 음성과 공급자 연결을 먼저 준비해주세요.
          </p>
        )}
        <form onSubmit={(event) => void submit(event)} className="conversation-form">
          <label className="check-field">
            <input
              type="checkbox"
              checked={consent}
              onChange={(e) => {
                if (e.target.checked) setConsent(true)
                else revoke()
              }}
            />
            기억·질문을 OpenAI에, 답변을 ElevenLabs에 전송합니다. 마이크 질문은 Deepgram에서
            전사하는 데 동의합니다.
          </label>
          <label className="sr-only" htmlFor="conversation-question">
            대화할 질문
          </label>
          <textarea
            id="conversation-question"
            maxLength={500}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="예: 우리 같이 제주도 갔을 때 기억나?"
            disabled={!ready || busy || recorder.recording}
          />
          <div className="composer-actions">
            <button
              type="button"
              disabled={!ready || !consent || !state.providers.transcription || busy || starting}
              onClick={() => {
                if (recorder.recording) void transcribe()
                else void start()
              }}
            >
              <Icon name="voice" size={18} />
              {recorder.recording ? `녹음 마치고 전사 · ${recorder.seconds}초` : '말로 질문'}
            </button>
            <span>
              {state.providers.transcription
                ? '전사 후 내용을 확인하고 보내세요'
                : '지금은 글로 질문할 수 있어요'}
            </span>
            <button
              className="primary"
              disabled={!ready || !consent || !text.trim() || busy || recorder.recording}
            >
              {busy ? '처리 중…' : '답변 만들기'}
              <Icon name="arrow" size={18} />
            </button>
          </div>
        </form>
      </div>
    </section>
  )
}
