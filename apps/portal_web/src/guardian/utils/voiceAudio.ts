export function pcm16Wav(buffers: Float32Array[], sourceRate: number) {
  const frames = buffers.reduce((sum, buffer) => sum + buffer.length, 0)
  const source = new Float32Array(frames); let offset = 0
  for (const buffer of buffers) { source.set(buffer, offset); offset += buffer.length }
  const targetRate = 16000; const count = Math.floor(frames * targetRate / sourceRate); const wav = new Uint8Array(44 + count * 2); const view = new DataView(wav.buffer)
  for (const [at, text] of [[0,'RIFF'],[8,'WAVE'],[12,'fmt '],[36,'data']] as const) for (let i = 0; i < 4; i++) view.setUint8(at + i, text.charCodeAt(i))
  view.setUint32(4, wav.length - 8, true); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, targetRate, true); view.setUint32(28, targetRate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); view.setUint32(40, count * 2, true)
  for (let i = 0; i < count; i++) { const position = i * sourceRate / targetRate; const base = Math.floor(position); const fraction = position - base; const value = Math.max(-1, Math.min(1, source[base] * (1 - fraction) + source[Math.min(base + 1, frames - 1)] * fraction)); view.setInt16(44 + i * 2, value < 0 ? value * 32768 : value * 32767, true) }
  source.fill(0); return wav
}

export function wavBase64(wav: Uint8Array) { let binary = ''; for (let i = 0; i < wav.length; i += 8192) binary += String.fromCharCode(...wav.subarray(i, i + 8192)); return btoa(binary) }
