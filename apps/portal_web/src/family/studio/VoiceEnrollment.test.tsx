import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { VoiceEnrollment } from './VoiceEnrollment'
import type { StudioState } from './api'

const state: StudioState = {
  profile: {
    guardian_name: '시험자',
    patient_alias: '가족',
    relationship: '딸',
    address_as: '아빠'
  },
  memories: [],
  voice: { status: 'none' },
  providers: { voice: true, conversation: false, transcription: false }
}
afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('목소리 녹음 소유권', () => {
  it('세 샘플을 보존해 한 번 전송하고 마이크를 종료한다', async () => {
    const processors: {
      onaudioprocess: ((event: unknown) => void) | null
      disconnect: ReturnType<typeof vi.fn>
      connect: ReturnType<typeof vi.fn>
    }[] = []
    const stop = vi.fn()
    vi.stubGlobal('navigator', {
      mediaDevices: { getUserMedia: vi.fn(async () => ({ getTracks: () => [{ stop }] })) }
    })
    vi.stubGlobal(
      'AudioContext',
      class {
        sampleRate = 16000
        destination = {}
        resume = async () => undefined
        close = async () => undefined
        createMediaStreamSource = () => ({ connect: vi.fn(), disconnect: vi.fn() })
        createScriptProcessor = () => {
          const processor = { onaudioprocess: null, connect: vi.fn(), disconnect: vi.fn() }
          processors.push(processor)
          return processor
        }
      }
    )
    vi.stubGlobal('URL', { createObjectURL: vi.fn(() => 'blob:sample'), revokeObjectURL: vi.fn() })
    const enroll = vi.fn(async () => true)
    const { unmount } = render(
      <VoiceEnrollment
        state={state}
        busy={false}
        enroll={enroll}
        action={vi.fn()}
        report={vi.fn()}
      />
    )
    expect(screen.getByRole('button', { name: '첫 샘플 녹음' })).toBeDisabled()
    fireEvent.click(screen.getByRole('checkbox'))
    for (let sample = 0; sample < 3; sample++) {
      fireEvent.click(
        screen.getByRole('button', { name: sample ? '다음 샘플 녹음' : '첫 샘플 녹음' })
      )
      await screen.findByRole('button', { name: '녹음 끝내고 저장' })
      act(() => {
        for (let frame = 0; frame < 80; frame++)
          processors[sample].onaudioprocess?.({
            inputBuffer: { getChannelData: () => new Float32Array(4096).fill((sample + 1) / 4) }
          })
      })
      fireEvent.click(screen.getByRole('button', { name: '녹음 끝내고 저장' }))
    }
    expect(stop).toHaveBeenCalledTimes(3)
    fireEvent.click(screen.getByRole('button', { name: '목소리 등록' }))
    await waitFor(() => expect(enroll).toHaveBeenCalledTimes(1))
    const samples = enroll.mock.calls[0] as unknown as [string[]]
    expect(samples[0]).toHaveLength(3)
    samples[0].forEach((sample) => expect(atob(sample).slice(0, 4)).toBe('RIFF'))
    expect(new Set(samples[0]).size).toBe(3)
    unmount()
    expect(processors.every((processor) => processor.onaudioprocess === null)).toBe(true)
  })
})
