import { describe, expect, it, vi } from 'vitest'
import type { VoiceStatus } from '../../shared/types/domain'
import { submitFreshVoiceEnrollment } from './useGuardianVoiceTrial'

const consent = '00000000-0000-4000-8000-000000000001'
const ready = (consent_id: string | null, upload_enabled = true): VoiceStatus => ({ authorized: true, ready: true, upload_enabled, status: 'none', consent_id })
const samples = [1, 2, 3].map(value => ({ durationMs: 20000, wav: new Uint8Array([value]) }))

describe('guardian voice enrollment ownership', () => {
  it.each([
    ['동의 철회', ready(consent, false)],
    ['동의 교체', ready('00000000-0000-4000-8000-000000000002')],
  ])('%s 후에는 생체자료를 POST하지 않는다', async (_label, fresh) => {
    const beforePost = vi.fn(); const post = vi.fn()
    const result = await submitFreshVoiceEnrollment({ controller: new AbortController(), capturedConsent: consent, samples, isCurrent: () => true, isConfirmed: () => true, fetchStatus: async () => fresh, beforePost, post })
    expect(result.submitted).toBe(false); expect(beforePost).not.toHaveBeenCalled(); expect(post).not.toHaveBeenCalled()
  })

  it('상태 조회 중 소유권이 취소되면 업로드를 시작하지 않는다', async () => {
    const controller = new AbortController(); const beforePost = vi.fn(); const post = vi.fn()
    const result = await submitFreshVoiceEnrollment({ controller, capturedConsent: consent, samples, isCurrent: () => true, isConfirmed: () => true, fetchStatus: async () => { controller.abort(); return ready(consent) }, beforePost, post })
    expect(controller.signal.aborted).toBe(true); expect(result.submitted).toBe(false); expect(beforePost).not.toHaveBeenCalled(); expect(post).not.toHaveBeenCalled()
  })

  it('유효한 현재 동의만 signal이 연결된 POST로 전달한다', async () => {
    const controller = new AbortController(); const beforePost = vi.fn(); const post = vi.fn()
    const result = await submitFreshVoiceEnrollment({ controller, capturedConsent: consent, samples, isCurrent: () => true, isConfirmed: () => true, fetchStatus: async () => ready(consent), beforePost, post })
    expect(result.submitted).toBe(true); expect(beforePost).toHaveBeenCalledOnce(); expect(post).toHaveBeenCalledWith(expect.objectContaining({ consent_id: consent, own_voice_confirmed: true, samples_wav_base64: expect.any(Array) }), controller.signal)
  })

  it('화면 이탈이 소유 controller를 취소하면 진행 중 POST도 중단한다', async () => {
    const controller = new AbortController(); let started!: () => void
    const posting = new Promise<void>(resolve => { started = resolve })
    const post = vi.fn((_payload: unknown, signal: AbortSignal) => new Promise<void>((_resolve, reject) => { started(); signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true }) }))
    const submission = submitFreshVoiceEnrollment({ controller, capturedConsent: consent, samples, isCurrent: () => true, isConfirmed: () => true, fetchStatus: async () => ready(consent), beforePost: vi.fn(), post })
    await posting; controller.abort()
    await expect(submission).rejects.toMatchObject({ name: 'AbortError' }); expect(post).toHaveBeenCalledWith(expect.any(Object), controller.signal)
  })
})
