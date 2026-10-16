import { useEffect, useRef, useState } from 'react'
import { pcm16Wav } from '../guardian/utils/voiceAudio'

type Capture = {
  stream: MediaStream
  context: AudioContext
  source: MediaStreamAudioSourceNode
  processor: ScriptProcessorNode
  buffers: Float32Array[]
  timer: number
}
export function useRecorder() {
  const capture = useRef<Capture | null>(null)
  const epoch = useRef(0)
  const [recording, setRecording] = useState(false)
  const [seconds, setSeconds] = useState(0)
  function stop(): Uint8Array | null {
    epoch.current++
    const active = capture.current
    if (!active) return null
    capture.current = null
    clearInterval(active.timer)
    active.processor.onaudioprocess = null
    active.processor.disconnect()
    active.source.disconnect()
    active.stream.getTracks().forEach((track) => track.stop())
    const wav = pcm16Wav(active.buffers, active.context.sampleRate)
    active.buffers.forEach((buffer) => buffer.fill(0))
    void active.context.close()
    setRecording(false)
    return wav
  }
  async function start() {
    if (capture.current) return
    const owner = ++epoch.current
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    if (epoch.current !== owner || document.hidden) {
      stream.getTracks().forEach((track) => track.stop())
      return
    }
    let context: AudioContext | null = null
    try {
      context = new AudioContext()
      await context.resume()
      if (epoch.current !== owner || document.hidden) {
        stream.getTracks().forEach((track) => track.stop())
        await context.close()
        return
      }
      const source = context.createMediaStreamSource(stream)
      const processor = context.createScriptProcessor(4096, 1, 1)
      const buffers: Float32Array[] = []
      processor.onaudioprocess = (event) => {
        const frames = buffers.reduce((sum, buffer) => sum + buffer.length, 0)
        if (capture.current?.stream === stream && frames < context!.sampleRate * 30)
          buffers.push(
            new Float32Array(
              event.inputBuffer.getChannelData(0).slice(0, context!.sampleRate * 30 - frames)
            )
          )
      }
      source.connect(processor)
      processor.connect(context.destination)
      const started = Date.now()
      const timer = window.setInterval(() => {
        const elapsed = Math.min(30, Math.floor((Date.now() - started) / 1000))
        setSeconds(elapsed)
        if (elapsed >= 30) {
          processor.disconnect()
          stream.getTracks().forEach((track) => track.stop())
          clearInterval(timer)
        }
      }, 100)
      capture.current = { stream, context, source, processor, buffers, timer }
      setSeconds(0)
      setRecording(true)
    } catch (error) {
      stream.getTracks().forEach((track) => track.stop())
      if (context) void context.close()
      throw error
    }
  }
  function cancel() {
    const wav = stop()
    wav?.fill(0)
  }
  useEffect(() => {
    const hide = () => {
      if (document.hidden) cancel()
    }
    document.addEventListener('visibilitychange', hide)
    return () => {
      epoch.current++
      const active = capture.current
      if (active) {
        clearInterval(active.timer)
        active.stream.getTracks().forEach((track) => track.stop())
        active.processor.onaudioprocess = null
        active.processor.disconnect()
        active.source.disconnect()
        active.buffers.forEach((b) => b.fill(0))
        void active.context.close()
        capture.current = null
      }
      document.removeEventListener('visibilitychange', hide)
    }
  }, [])
  return { start, stop, cancel, recording, seconds }
}
