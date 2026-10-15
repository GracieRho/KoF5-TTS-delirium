import { useEffect, useRef, useState } from 'react'
import { Icon } from '../../shared/components/Icon'
import { wavBase64 } from '../guardian/utils/voiceAudio'
import { useRecorder } from './useRecorder'
import type { StudioState } from './api'

type Props = {
  state: StudioState
  busy: boolean
  enroll: (samples: string[]) => Promise<boolean>
  action: (method: string, path: string) => Promise<void>
  report: (message: string) => void
}
const labels = {
  none: '아직 등록하지 않았어요',
  failed: '등록 거절 · 설정 확인 필요',
  deleted: '삭제된 음성',
  pending: '생성 결과 확인 중',
  verification_pending: '본인 인증 확인 필요',
  created: '대화에 사용할 준비 완료',
  deletion_pending: '삭제 확인 중 · 사용 중단'
}
const scripts = [
  '오늘은 햇살이 참 좋네요. 창밖으로 보이는 나무도 초록빛이에요. 편하게 앉아서 천천히 이야기 나눠요. 요즘 좋아하는 음식이나 자주 듣는 노래가 있나요? 저는 함께 웃으며 보냈던 시간이 생각나요. 서두르지 않아도 괜찮아요.',
  '함께 다녀온 여행이 떠오르네요. 길을 걸으며 이런저런 이야기를 나누고 맛있는 음식을 먹었어요. 다음에는 어떤 풍경을 보고 싶나요? 바다도 좋고 조용한 숲도 좋아요. 익숙하고 편안한 곳을 생각하면서 천천히 말씀해주세요.',
  '좋아하는 음악을 들으며 차 한 잔 마시는 시간이 좋아요. 특별한 이야기가 아니어도 괜찮아요. 예전에 즐겨 하던 일이나 기억에 남는 하루가 있나요? 저는 소소한 일상을 나누는 순간이 참 소중해요. 편한 속도로 이야기해요.'
]
export function VoiceEnrollment({ state, busy, enroll, action, report }: Props) {
  const recorder = useRecorder()
  const [confirmed, setConfirmed] = useState(false)
  const [samples, setSamples] = useState<Uint8Array[]>([])
  const [starting, setStarting] = useState(false)
  const [preview, setPreview] = useState<string | null>(null)
  const ownedSamples = useRef(samples)
  ownedSamples.current = samples
  useEffect(
    () => () => {
      ownedSamples.current.forEach((wav) => wav.fill(0))
    },
    []
  )
  useEffect(() => {
    if (!preview) return
    return () => URL.revokeObjectURL(preview)
  }, [preview])
  const available =
    state.providers.voice &&
    Boolean(state.profile.guardian_name) &&
    ['none', 'failed', 'deleted'].includes(state.voice.status)
  async function start() {
    setStarting(true)
    try {
      await recorder.start()
    } catch {
      report('마이크 권한과 연결을 확인해주세요.')
    } finally {
      setStarting(false)
    }
  }
  function stop() {
    const wav = recorder.stop()
    if (!wav) return
    const duration = (wav.length - 44) / 32
    if (duration < 20000 || duration > 30000) {
      wav.fill(0)
      report('샘플은 20~30초로 녹음해주세요.')
      return
    }
    setPreview(URL.createObjectURL(new Blob([wav.slice().buffer], { type: 'audio/wav' })))
    setSamples((old) => [...old, wav].slice(0, 3))
  }
  function clear() {
    recorder.cancel()
    samples.forEach((wav) => wav.fill(0))
    setSamples([])
    setPreview(null)
  }
  return (
    <section>
      <div className="section-heading">
        <div>
          <h1>익숙한 목소리</h1>
          <p className="compact">평소 이야기하듯, 편안한 목소리로 읽어주세요.</p>
        </div>
        <span className="state-label">{labels[state.voice.status]}</span>
      </div>
      <div className="voice-layout">
        <div className="voice-recorder">
          <div className={`voice-symbol ${recorder.recording ? 'is-recording' : ''}`}>
            <Icon name="voice" size={34} />
          </div>
          <h2>
            {state.voice.status === 'created'
              ? `${state.profile.guardian_name}님의 목소리가 준비됐어요`
              : '당신의 목소리를 담아요'}
          </h2>
          <p>
            20~30초씩 세 번, 총 1분 이상 녹음합니다.
            <br />
            배경 소음이 없는 곳에서 같은 말투로 읽어주세요.
          </p>
          <div className="sample-progress" aria-label={`샘플 ${samples.length}/3개 준비`}>
            {[0, 1, 2].map((i) => (
              <span key={i} className={samples.length > i ? 'complete' : ''}>
                {samples.length > i ? <Icon name="check" size={18} /> : `0${i + 1}`}
              </span>
            ))}
          </div>
          <div className="record-time" aria-live="polite">
            {recorder.recording
              ? `00:${String(recorder.seconds).padStart(2, '0')}`
              : `${samples.length} / 3 샘플`}
          </div>
          {recorder.recording ? (
            <button className="primary" onClick={stop}>
              녹음 끝내고 저장
            </button>
          ) : (
            <button
              className="primary"
              disabled={!available || !confirmed || busy || starting || samples.length >= 3}
              onClick={() => void start()}
            >
              <Icon name="voice" size={18} />
              {starting ? '마이크 확인 중' : samples.length ? '다음 샘플 녹음' : '첫 샘플 녹음'}
            </button>
          )}
          {preview && <audio controls src={preview} aria-label="마지막 녹음 미리 듣기" />}
          <label className="check-field">
            <input
              type="checkbox"
              checked={confirmed}
              disabled={busy}
              onChange={(e) => {
                setConfirmed(e.target.checked)
                if (!e.target.checked) clear()
              }}
            />
            내 목소리이며, 복제를 위해 녹음을 ElevenLabs에 전송하는 데 동의합니다.
          </label>
          <div className="button-row">
            <button
              disabled={
                !available || !confirmed || samples.length !== 3 || busy || recorder.recording
              }
              onClick={async () => {
                const encoded = samples.map(wavBase64)
                clear()
                await enroll(encoded)
              }}
            >
              목소리 등록
            </button>
            <button disabled={!samples.length || busy} onClick={clear}>
              다시 녹음
            </button>
          </div>
          {!state.providers.voice && (
            <p className="blocking-note">
              음성 공급자 연결 전입니다. 서버에 ElevenLabs 키를 연결하면 등록할 수 있어요.
            </p>
          )}
          {['pending', 'verification_pending'].includes(state.voice.status) && (
            <button disabled={busy} onClick={() => void action('POST', '/voice/reconcile')}>
              원격 상태 확인
            </button>
          )}
          {!['none', 'failed', 'deleted'].includes(state.voice.status) && (
            <button
              className="danger"
              disabled={busy}
              onClick={() => void action('DELETE', '/voice')}
            >
              복제 음성 사용 중단 및 삭제
            </button>
          )}
        </div>
        <aside className="reading-guide">
          <h2>읽기 가이드</h2>
          <p className="compact">
            문장을 외울 필요는 없어요. 자연스럽게 읽고, 20초가 지나면 녹음을 마쳐주세요.
          </p>
          <blockquote>{scripts[Math.min(samples.length, 2)]}</blockquote>
          <div className="guide-rule">
            <Icon name="shield" />
            <p>
              현재는 동의한 성인 본인의 목소리와 가상 가족 정보만 사용할 수 있습니다. 실제 환자
              대상 사용은 지원하지 않으며 원본 녹음은 서버에 저장하지 않습니다.
            </p>
          </div>
        </aside>
      </div>
    </section>
  )
}
