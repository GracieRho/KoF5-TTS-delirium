import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Studio } from './Studio'
import { MemoryLibrary } from './MemoryLibrary'
import { Conversation } from './Conversation'
import { studioRequest, type StudioState } from './api'

const state: StudioState = {
  profile: {
    guardian_name: '시험자',
    patient_alias: '가상 가족',
    relationship: '딸',
    address_as: '아빠'
  },
  memories: [
    {
      id: 'one',
      title: '제주도 여행',
      category: 'story',
      content: '함께 산책했다.',
      created_at: '2026-10-15T00:00:00Z'
    }
  ],
  voice: { status: 'none' },
  providers: { voice: false, conversation: false, transcription: false }
}
beforeEach(() => {
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute('open', '')
  }
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute('open')
  }
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined)
})
afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('가족 시연 공간', () => {
  it('연결된 실제 상태를 표시하고 공급자 없이 등록 성공을 표시하지 않는다', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => state }))
    render(<Studio />)
    expect(await screen.findByText('2 / 3 준비 완료')).toBeInTheDocument()
    fireEvent.click(screen.getAllByRole('button', { name: '목소리 등록' })[0])
    expect(
      await screen.findByText(
        '음성 공급자 연결 전입니다. 서버에 ElevenLabs 키를 연결하면 등록할 수 있어요.'
      )
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '첫 샘플 녹음' })).toBeDisabled()
  })

  it('로컬 서버가 없으면 재연결 동작을 제공한다', async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce({ ok: true, json: async () => state })
    vi.stubGlobal('fetch', fetch)
    render(<Studio />)
    expect(
      await screen.findByRole('heading', { name: '시연 서버 연결이 필요해요' })
    ).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '다시 연결' }))
    expect(await screen.findByText('2 / 3 준비 완료')).toBeInTheDocument()
  })

  it('실패한 기억 저장은 편집 시트를 닫지 않는다', async () => {
    const save = vi.fn().mockResolvedValue(false)
    render(<MemoryLibrary memories={state.memories} busy={false} save={save} remove={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /제주도 여행/ }))
    fireEvent.click(screen.getByRole('button', { name: '기억 저장' }))
    await waitFor(() => expect(save).toHaveBeenCalled())
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByDisplayValue('제주도 여행')).toBeInTheDocument()
  })

  it('전송 동의가 있어야 기억을 담은 질문을 보내고 음성을 돌려받는다', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValue({
          ok: true,
          json: async () => ({
            reply: '함께 산책했어요.',
            audio_base64: btoa('fake-mp3'),
            memory_count: 1
          })
        })
    )
    vi.stubGlobal('URL', { createObjectURL: vi.fn(() => 'blob:test'), revokeObjectURL: vi.fn() })
    render(
      <Conversation
        state={{
          ...state,
          voice: { status: 'created' },
          providers: { ...state.providers, voice: true, conversation: true }
        }}
        report={vi.fn()}
      />
    )
    fireEvent.change(screen.getByLabelText('대화할 질문'), { target: { value: '제주도 기억나?' } })
    expect(screen.getByRole('button', { name: '답변 만들기' })).toBeDisabled()
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.click(screen.getByRole('button', { name: '답변 만들기' }))
    expect(await screen.findByText('함께 산책했어요.')).toBeInTheDocument()
    expect(screen.getByLabelText('복제 목소리로 답변 듣기')).toHaveAttribute('src', 'blob:test')
    const sent = JSON.parse(vi.mocked(fetch).mock.calls[0][1]!.body as string)
    expect(sent).toEqual({ text: '제주도 기억나?', provider_processing_consent: true })
    fireEvent.click(screen.getByRole('checkbox'))
    expect(screen.queryByText('함께 산책했어요.')).not.toBeInTheDocument()
  })

  it('API는 전용 헤더를 보내고 서버의 오류를 전달한다', async () => {
    const fetch = vi
      .fn()
      .mockResolvedValue({ ok: false, json: async () => ({ detail: '음성 설정이 필요합니다.' }) })
    vi.stubGlobal('fetch', fetch)
    await expect(studioRequest('/voice', 'POST', {})).rejects.toThrow('음성 설정이 필요합니다.')
    expect(fetch.mock.calls[0][1].headers['X-Kof5-Studio']).toBe('1')
  })
})
