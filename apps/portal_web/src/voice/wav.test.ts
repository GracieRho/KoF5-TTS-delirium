import { expect, it } from 'vitest'
import { pcm16Wav, sampleSeconds } from './wav'

it('resamples 48 kHz mono input to a signed 16-bit WAV at 16 kHz', async () => {
  const source = new Float32Array(48000)
  source[0] = 1
  const wav = pcm16Wav([source], 48000)
  const data = await new Promise<ArrayBuffer>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result as ArrayBuffer)
    reader.onerror = reject
    reader.readAsArrayBuffer(wav)
  })
  const header = new DataView(data)
  expect(wav.type).toBe('audio/wav')
  expect(sampleSeconds(wav)).toBe(1)
  expect(header.getUint16(22, true)).toBe(1)
  expect(header.getUint32(24, true)).toBe(16000)
  expect(header.getUint16(34, true)).toBe(16)
  expect(header.getUint32(40, true)).toBe(32000)
  expect(header.getInt16(44, true)).toBe(32767)
})
