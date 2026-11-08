import { useEffect, useRef, useState } from 'react'
import { MAX_SECONDS, MIN_SECONDS, pcm16Wav, sampleSeconds } from './wav'

type Capture = {
  stream: MediaStream
  context: AudioContext
  source: MediaStreamAudioSourceNode
  processor: ScriptProcessorNode
  filter: BiquadFilterNode | null
  buffers: Float32Array[]
  timer: number
}

export function useRecorder() {
  const active = useRef<Capture | null>(null)
  const version = useRef(0)
  const pending = useRef<AudioContext | null>(null)
  const [mode, setMode] = useState<'idle' | 'requesting' | 'recording'>('idle')
  const [sample, setSample] = useState<Blob | null>(null)
  const [error, setError] = useState('')
  const [seconds, setSeconds] = useState(0)

  function finish(keep: boolean) {
    version.current++
    if (pending.current) {
      const context = pending.current
      pending.current = null
      void context.close().catch(() => {})
    }
    const capture = active.current
    active.current = null
    setMode('idle')
    if (!capture) return
    window.clearTimeout(capture.timer)
    capture.processor.onaudioprocess = null
    capture.processor.disconnect()
    capture.source.disconnect()
    capture.filter?.disconnect()
    capture.stream.getTracks().forEach(track => track.stop())
    void capture.context.close().catch(() => {})
    if (keep) {
      const wav = pcm16Wav(capture.buffers, capture.context.sampleRate)
      if (sampleSeconds(wav) >= MIN_SECONDS) setSample(wav)
      else setError('녹음이 짧습니다. 10초 이상 말씀하신 후 다시 시도해 주세요.')
    }
    for (const buffer of capture.buffers) buffer.fill(0)
  }

  async function start() {
    const owner = ++version.current
    setError('')
    setSample(null)
    setSeconds(0)
    if (!navigator.mediaDevices?.getUserMedia) {
      setError('이 브라우저에서 마이크를 열 수 없습니다. HTTPS 주소에서 마이크 권한을 확인해 주세요.')
      return
    }
    setMode('requesting')
    let stream: MediaStream | undefined
    let context: AudioContext | undefined
    try {
      // Resume from the initiating gesture, as required by iPad Safari.
      context = new AudioContext()
      pending.current = context
      await context.resume()
      if (owner !== version.current || document.hidden) return
      stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } })
      if (owner !== version.current || document.hidden) return
      const source = context.createMediaStreamSource(stream)
      const processor = context.createScriptProcessor(4096, 1, 1)
      const buffers: Float32Array[] = []
      let frames = 0
      const sampleRate = context.sampleRate
      const maximumFrames = sampleRate * MAX_SECONDS
      processor.onaudioprocess = event => {
        const input = event.inputBuffer.getChannelData(0)
        const count = Math.min(input.length, maximumFrames - frames)
        buffers.push(input.slice(0, count))
        frames += count
        setSeconds(Math.floor(frames / sampleRate))
        if (frames >= maximumFrames) finish(true)
      }
      // Suppress frequencies above the output Nyquist limit before downsampling.
      const filter = sampleRate > 16000 ? context.createBiquadFilter() : null
      if (filter) {
        filter.type = 'lowpass'
        filter.frequency.value = 7400
        filter.Q.value = Math.SQRT1_2
        source.connect(filter)
        filter.connect(processor)
      } else {
        source.connect(processor)
      }
      processor.connect(context.destination)
      const timer = window.setTimeout(() => finish(true), MAX_SECONDS * 1000)
      pending.current = null
      active.current = { stream, context, source, processor, filter, buffers, timer }
      for (const track of stream.getAudioTracks()) {
        track.addEventListener('ended', () => {
          if (active.current?.stream !== stream) return
          finish(false)
          setError('마이크 연결이 끊겼습니다. 연결한 뒤 다시 녹음해 주세요.')
        }, { once: true })
      }
      setMode('recording')
    } catch {
      if (owner === version.current) {
        setMode('idle')
        setError('마이크를 열 수 없습니다. 브라우저의 마이크 권한과 연결 상태를 확인해 주세요.')
      }
    } finally {
      if (pending.current === context) pending.current = null
      if (!stream || active.current?.stream !== stream) {
        stream?.getTracks().forEach(track => track.stop())
        if (context?.state !== 'closed') void context?.close().catch(() => {})
      }
    }
  }

  useEffect(() => {
    const hide = () => { if (document.hidden) finish(false) }
    const exit = () => finish(false)
    document.addEventListener('visibilitychange', hide)
    window.addEventListener('pagehide', exit)
    return () => {
      document.removeEventListener('visibilitychange', hide)
      window.removeEventListener('pagehide', exit)
      finish(false)
    }
  }, [])

  return { mode, sample, error, seconds, start, stop: () => finish(true), discard: () => {
    finish(false)
    setSample(null)
    setError('')
  } }
}

export function useObjectUrl(blob: Blob | null) {
  const [entry, setEntry] = useState<{ blob: Blob; url: string } | null>(null)
  useEffect(() => {
    if (!blob) { setEntry(null); return }
    const url = URL.createObjectURL(blob)
    setEntry({ blob, url })
    return () => URL.revokeObjectURL(url)
  }, [blob])
  return entry?.blob === blob ? entry?.url : undefined
}
