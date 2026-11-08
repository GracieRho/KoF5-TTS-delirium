// Preserve the studio's mono, 16 kHz PCM format across device sampling rates.
export const SAMPLE_RATE = 16000
export const MIN_SECONDS = 10
export const MAX_SECONDS = 120

export function pcm16Wav(buffers: Float32Array[], sourceRate: number): Blob {
  const frames = buffers.reduce((sum, buffer) => sum + buffer.length, 0)
  const source = new Float32Array(frames)
  let offset = 0
  for (const buffer of buffers) {
    source.set(buffer, offset)
    offset += buffer.length
  }
  const count = Math.min(MAX_SECONDS * SAMPLE_RATE, Math.floor(frames * SAMPLE_RATE / sourceRate))
  const wav = new ArrayBuffer(44 + count * 2)
  const view = new DataView(wav)
  for (const [position, tag] of [[0, 'RIFF'], [8, 'WAVE'], [12, 'fmt '], [36, 'data']] as const) {
    for (let i = 0; i < tag.length; i++) view.setUint8(position + i, tag.charCodeAt(i))
  }
  view.setUint32(4, wav.byteLength - 8, true)
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, SAMPLE_RATE, true)
  view.setUint32(28, SAMPLE_RATE * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  view.setUint32(40, count * 2, true)
  for (let i = 0; i < count; i++) {
    const position = i * sourceRate / SAMPLE_RATE
    const base = Math.floor(position)
    const fraction = position - base
    const interpolated = source[base] * (1 - fraction) + source[Math.min(base + 1, frames - 1)] * fraction
    const value = Math.max(-1, Math.min(1, interpolated))
    view.setInt16(44 + i * 2, value < 0 ? value * 32768 : value * 32767, true)
  }
  source.fill(0)
  return new Blob([wav], { type: 'audio/wav' })
}

export function sampleSeconds(wav: Blob) {
  return (wav.size - 44) / (2 * SAMPLE_RATE)
}
