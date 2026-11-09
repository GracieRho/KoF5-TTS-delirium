import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import type { VoiceStatus } from './api'
import * as capture from './useRecorder'
import { VoiceWorkspace, type Perform } from './VoiceWorkspace'

const perform: Perform = async (_label, action) => { await action() }
const status: VoiceStatus = { configured: true, reference: 'voice-reference', voice_state: 'empty' }

afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks() })

it('requires recording consent and a confirmed voice before synthesis', () => {
  render(<VoiceWorkspace status={status} busy={false} locked={false} perform={perform} />)
  expect(screen.getByRole('button', { name: '녹음 시작' })).toBeDisabled()
  expect(screen.getByRole('button', { name: '음성 만들기' })).toBeDisabled()
  fireEvent.click(screen.getByRole('checkbox'))
  expect(screen.getByRole('button', { name: '녹음 시작' })).toBeEnabled()
})

it('does not submit text for a voice pending verification', () => {
  render(<VoiceWorkspace status={{ ...status, voice_state: 'verification' }} busy={false} locked={false} perform={perform} />)
  expect(screen.getByRole('heading', { name: 'ElevenLabs 본인 확인 필요' })).toBeVisible()
  expect(screen.getByLabelText('읽을 문장')).toBeDisabled()
})

it('sends the exact text with the displayed voice reference and shows a downloadable MP3', async () => {
  const fetch = vi.fn().mockResolvedValue(new Response(new Uint8Array([1, 2, 3]), { headers: { 'Content-Type': 'audio/mpeg' } }))
  vi.stubGlobal('fetch', fetch)
  vi.stubGlobal('URL', { createObjectURL: () => 'blob:mock', revokeObjectURL: () => {} })
  render(<VoiceWorkspace status={{ ...status, voice_state: 'ready' }} busy={false} locked={false} perform={perform} />)
  const text = ' 안녕하세요.\n오늘도 보고 싶어요.'
  fireEvent.change(screen.getByLabelText('읽을 문장'), { target: { value: text } })
  fireEvent.click(screen.getByRole('button', { name: '음성 만들기' }))
  expect(await screen.findByRole('link', { name: 'MP3 다운로드' })).toHaveAttribute('download', 'favilium-message.mp3')
  expect(fetch).toHaveBeenCalledWith('/api/speech', expect.objectContaining({
    headers: { 'Content-Type': 'application/json', 'X-Voice-Reference': 'voice-reference' },
    body: JSON.stringify({ text }),
  }))
  fireEvent.change(screen.getByLabelText('읽을 문장'), { target: { value: '다른 문장' } })
  expect(screen.queryByRole('link', { name: 'MP3 다운로드' })).toBeNull()
})

it('requires confirmation and binds deletion to the voice shown in the studio', async () => {
  const fetch = vi.fn().mockResolvedValue(new Response('{}'))
  vi.stubGlobal('fetch', fetch)
  render(<VoiceWorkspace status={{ ...status, voice_state: 'ready' }} busy={false} locked={false} perform={perform} />)
  fireEvent.click(screen.getByRole('button', { name: '등록한 목소리 삭제' }))
  expect(fetch).not.toHaveBeenCalled()
  fireEvent.click(screen.getByRole('button', { name: '삭제 확인' }))
  expect(fetch).toHaveBeenCalledWith('/api/voice', expect.objectContaining({
    method: 'DELETE', headers: { 'X-Voice-Reference': 'voice-reference' },
  }))
})

it.each([
  { configured: false, locked: false },
  { configured: true, locked: true },
])('allows local preview but blocks sending the sample while $configured/$locked', ({ configured, locked }) => {
  vi.spyOn(capture, 'useRecorder').mockReturnValue({
    sample: new Blob([new Uint8Array(320044)]), mode: 'idle', seconds: 10, error: '',
    start: vi.fn(), stop: vi.fn(), discard: vi.fn(),
  })
  vi.stubGlobal('URL', { createObjectURL: () => 'blob:sample', revokeObjectURL: () => {} })
  render(<VoiceWorkspace status={{ ...status, configured }} busy={false} locked={locked} perform={perform} />)
  fireEvent.click(screen.getByRole('checkbox'))
  expect(screen.getByLabelText('녹음한 보호자 목소리 미리 듣기')).toBeVisible()
  expect(screen.getByRole('button', { name: '다시 녹음' })).toBeEnabled()
  expect(screen.getByRole('button', { name: '이 녹음으로 목소리 등록' })).toBeDisabled()
})
