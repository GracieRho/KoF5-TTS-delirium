import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { RequestEpoch, retainOwnedStream } from '../../shared/hooks/requestEpoch'
import type { VoiceStatus } from '../../shared/types/domain'
import { UUID } from '../../shared/types/constants'
import { pcm16Wav, wavBase64 } from '../utils/voiceAudio'

type Sample = { durationMs: number; wav: Uint8Array }
type Capture = { owner: number; stream: MediaStream; context: AudioContext; source: MediaStreamAudioSourceNode; processor: ScriptProcessorNode; buffers: Float32Array[]; startedAt: number; timer: number }
export function voiceReady(status: VoiceStatus | null) { return status?.authorized === true && status.ready === true && status.upload_enabled === true && status.status === 'none' && UUID.test(status.consent_id ?? '') }

export function useGuardianVoiceTrial(patientId: string, token: string, enabled: boolean) {
  const { handleAuthError } = useAuth(); const epoch = useRef(new RequestEpoch()); const mounted = useRef(true); const capture = useRef<Capture | null>(null)
  const [remote, setRemote] = useState<VoiceStatus | null>(null); const [samples, setSamples] = useState<Sample[]>([]); const [recording, setRecording] = useState(false); const [busy, setBusy] = useState(false); const [ownConfirmed, setOwnConfirmedState] = useState(false); const [status, setStatus] = useState('별도 동의와 합성 시험 상태를 확인하세요.')
  const base = `/internal/synthetic/guardian/${patientId}/voice`
  const request = useCallback(async <T,>(path: string, method = 'GET', body?: unknown, signal?: AbortSignal) => { const response = await fetch(base + path, { method, headers: { Authorization: `Bearer ${token}`, 'X-Synthetic-Material': 'confirmed', ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined, signal }); if (response.status === 401 || response.status === 403) handleAuthError(token); if (!response.ok) throw new Error(String(response.status)); return response.json() as Promise<T> }, [base, token, handleAuthError])
  const release = useCallback((keep = false) => { const owned = capture.current; if (!owned) return; window.clearInterval(owned.timer); owned.processor.onaudioprocess = null; owned.processor.disconnect(); owned.source.disconnect(); owned.stream.getTracks().forEach(track => track.stop()); void owned.context.close(); if (!keep) owned.buffers.length = 0; capture.current = null; if (mounted.current) setRecording(false) }, [])
  const refresh = useCallback(async () => {
    if (!enabled) return
    const owner = epoch.current.begin(); setBusy(true)
    try { const next = await request<VoiceStatus>('/status'); if (!epoch.current.owns(owner) || !mounted.current) return; setRemote(next); setStatus(!next.authorized ? '현재 보호자 연결이 확인되지 않았습니다.' : next.status === 'created' ? '합성 복제의 원격 생성이 확인됐습니다. 임상 사용 승인은 아닙니다.' : next.status === 'pending' || next.status === 'verification_pending' ? '합성 생성 확인 대기 중입니다. 같은 샘플을 다시 올리지 마세요.' : next.status === 'deletion_pending' ? '삭제 요청 확인 대기 중입니다.' : next.status === 'deleted' ? '원격 부재 확인 뒤 삭제가 확인됐습니다.' : voiceReady(next) ? '테스터 본인 음성만 20~30초씩 세 번 녹음하세요.' : '별도 동의 또는 합성 업로드가 준비되지 않았습니다.') }
    catch { if (epoch.current.owns(owner) && mounted.current) { setRemote(null); setStatus('합성 음성 상태를 확인하지 못했습니다. 녹음과 업로드를 닫습니다.') } }
    finally { if (epoch.current.owns(owner) && mounted.current) setBusy(false) }
  }, [enabled, request])
  useEffect(() => { mounted.current = true; epoch.current.invalidate(); release(); setSamples([]); setOwnConfirmedState(false); void refresh(); return () => { mounted.current = false; epoch.current.invalidate(); release() } }, [patientId, token, refresh, release])
  useEffect(() => { const hide = () => { if (document.hidden) { epoch.current.invalidate(); release(); setSamples([]); setOwnConfirmedState(false); setStatus('화면이 숨겨져 오디오 참조를 해제했습니다.') } }; document.addEventListener('visibilitychange', hide); return () => document.removeEventListener('visibilitychange', hide) }, [release])
  function setOwnConfirmed(value: boolean) { setOwnConfirmedState(value); if (!value) { epoch.current.invalidate(); release(); setSamples([]); setStatus('본인 음성 확인을 해제해 오디오 참조를 해제했습니다.') } }
  async function start() {
    if (!ownConfirmed || !voiceReady(remote) || capture.current || samples.length >= 3) return
    const owner = epoch.current.begin(); const consent = remote!.consent_id; const controller = new AbortController(); setBusy(true); let stream: MediaStream | null = null
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 }, video: false })
      if (!retainOwnedStream(epoch.current, owner, stream, mounted.current && ownConfirmed && !document.hidden)) return
      const fresh = await request<VoiceStatus>('/status', 'GET', undefined, controller.signal)
      if (!retainOwnedStream(epoch.current, owner, stream, mounted.current && ownConfirmed && !document.hidden && voiceReady(fresh) && fresh.consent_id === consent)) return
      const context = new AudioContext(); const source = context.createMediaStreamSource(stream); const processor = context.createScriptProcessor(4096, 1, 1); const owned: Capture = { owner, stream, context, source, processor, buffers: [], startedAt: Date.now(), timer: 0 }
      processor.onaudioprocess = event => { event.outputBuffer.getChannelData(0).fill(0); if (capture.current === owned && epoch.current.owns(owner)) owned.buffers.push(new Float32Array(event.inputBuffer.getChannelData(0))) }; source.connect(processor); processor.connect(context.destination); await context.resume()
      if (!epoch.current.owns(owner) || !mounted.current || !ownConfirmed || document.hidden) { processor.disconnect(); source.disconnect(); stream.getTracks().forEach(track => track.stop()); void context.close(); return }
      capture.current = owned; setRecording(true); owned.timer = window.setInterval(() => { if (capture.current === owned && epoch.current.owns(owner) && Date.now() - owned.startedAt >= 30000) stop(true) }, 100); setStatus('테스터 본인 음성을 로컬 메모리에서만 녹음 중입니다.')
    } catch { stream?.getTracks().forEach(track => track.stop()); if (epoch.current.owns(owner) && mounted.current) setStatus('마이크 또는 동의 상태를 확인하지 못해 녹음을 시작하지 않았습니다.') }
    finally { if (epoch.current.owns(owner) && mounted.current) setBusy(false) }
  }
  function stop(save = true) { const owned = capture.current; if (!owned || !epoch.current.owns(owned.owner)) return; const elapsed = Date.now() - owned.startedAt; let sample: Sample | null = null; if (save && ownConfirmed && elapsed >= 20000 && elapsed <= 30500 && owned.buffers.length) { const wav = pcm16Wav(owned.buffers, owned.context.sampleRate); const durationMs = (wav.length - 44) / 32; if (wav.length <= 2_000_000 && durationMs >= 20000 && durationMs <= 30000) sample = { durationMs, wav } } release(Boolean(sample)); if (sample) { setSamples(old => [...old, sample!].slice(0, 3)); setStatus('샘플을 로컬 메모리에만 보관했습니다.') } else setStatus('20~30초 조건을 채우지 못해 오디오 참조를 해제했습니다.') }
  async function enroll() {
    if (!ownConfirmed || !voiceReady(remote) || samples.length !== 3) return
    const owner = epoch.current.begin(); setBusy(true); const payload = { consent_id: remote!.consent_id, request_key: crypto.randomUUID(), own_voice_confirmed: ownConfirmed, samples_wav_base64: samples.map(sample => wavBase64(sample.wav)) }; setSamples([])
    try { await request('/enroll', 'POST', payload); if (!epoch.current.owns(owner) || !mounted.current) return; setStatus('업로드 요청을 접수했습니다. 원격 상태를 다시 확인합니다.'); await refresh() }
    catch { if (epoch.current.owns(owner) && mounted.current) { setRemote(null); setStatus('업로드 결과가 불명확합니다. 재전송하지 말고 상태를 다시 확인하세요.') } }
    finally { if (epoch.current.owns(owner) && mounted.current) setBusy(false) }
  }
  async function mutate(action: 'delete' | 'reconcile') { if (!remote?.clone_id || !UUID.test(remote.clone_id)) return; const owner = epoch.current.begin(); setBusy(true); try { await request(`/${remote.clone_id}/${action}`, 'POST'); if (epoch.current.owns(owner) && mounted.current) await refresh() } catch { if (epoch.current.owns(owner) && mounted.current) setStatus('원격 결과가 불명확합니다. 완료로 표시하지 않았습니다.') } finally { if (epoch.current.owns(owner) && mounted.current) setBusy(false) } }
  return { remote, samples, recording, busy, status, ready: voiceReady(remote), ownConfirmed, setOwnConfirmed, start, stop, enroll, refresh, mutate }
}
