import { describe, expect, it } from 'vitest'
import { pcm16Wav } from './voiceAudio'
import { voiceReady } from '../hooks/useGuardianVoiceTrial'

describe('합성 음성 샘플', () => {
  it('16 kHz PCM WAV 헤더와 길이를 만든다', () => {
    const wav = pcm16Wav([new Float32Array(16000)], 16000)
    expect(new TextDecoder().decode(wav.subarray(0, 4))).toBe('RIFF'); expect(wav.length).toBe(32044)
  })
  it('별도 동의와 업로드 조건이 모두 확인돼야 녹음을 연다', () => {
    expect(voiceReady({ authorized: true, ready: true, upload_enabled: true, status: 'none', consent_id: '00000000-0000-4000-8000-000000000001' })).toBe(true)
    expect(voiceReady({ authorized: true, ready: true, upload_enabled: false, status: 'none', consent_id: '00000000-0000-4000-8000-000000000001' })).toBe(false)
  })
})
