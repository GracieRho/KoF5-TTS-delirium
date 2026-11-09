import { StrictMode } from 'react'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { App } from './App'

const emptyWorkspace = { configured: true, reference: null, voice_state: 'empty' }
afterEach(() => vi.unstubAllGlobals())

it('opens the recorder immediately and coalesces duplicate bootstrap and focus requests', async () => {
  let finish!: (response: Response) => void
  const fetch = vi.fn(() => new Promise<Response>(resolve => { finish = resolve }))
  vi.stubGlobal('fetch', fetch)
  render(<StrictMode><App /></StrictMode>)
  expect(screen.getByRole('heading', { name: '보호자 목소리 등록' })).toBeVisible()
  expect(screen.queryByLabelText('접속 코드')).toBeNull()
  expect(screen.queryByRole('button', { name: '로그아웃' })).toBeNull()
  fireEvent(window, new Event('focus'))
  expect(fetch).toHaveBeenCalledTimes(1)
  expect(fetch).toHaveBeenCalledWith('/api/workspace', expect.objectContaining({ method: 'POST', credentials: 'same-origin' }))
  await act(async () => { finish(Response.json(emptyWorkspace)) })
  expect(screen.getByRole('button', { name: '녹음 시작' })).toBeDisabled()
  fireEvent.click(screen.getByRole('checkbox'))
  expect(screen.getByRole('button', { name: '녹음 시작' })).toBeEnabled()
})

it('keeps local recording available during an outage and restores the existing voice after retry', async () => {
  const fetch = vi.fn()
    .mockResolvedValueOnce(Response.json({ detail: '저장소에 연결할 수 없습니다.' }, { status: 503 }))
    .mockResolvedValueOnce(Response.json({ ...emptyWorkspace, voice_state: 'ready', reference: 'sample-reference' }))
  vi.stubGlobal('fetch', fetch)
  render(<App />)
  expect(await screen.findByRole('alert')).toHaveTextContent('저장소에 연결할 수 없습니다.')
  fireEvent.click(screen.getByRole('checkbox'))
  expect(screen.getByRole('button', { name: '녹음 시작' })).toBeEnabled()
  expect(screen.getByRole('button', { name: '음성 만들기' })).toBeDisabled()
  fireEvent.click(screen.getByRole('button', { name: '상태 다시 확인' }))
  expect(await screen.findByRole('heading', { name: '목소리 등록 완료' })).toBeVisible()
  expect(screen.getByLabelText('읽을 문장')).toBeEnabled()
  expect(fetch).toHaveBeenCalledTimes(2)
})

it('reuses one pending workspace request across a real unmount and remount', async () => {
  let finish!: (response: Response) => void
  const fetch = vi.fn(() => new Promise<Response>(resolve => { finish = resolve }))
  vi.stubGlobal('fetch', fetch)
  const first = render(<App />)
  first.unmount()
  render(<App />)
  await act(async () => { finish(Response.json({ ...emptyWorkspace, configured: false })) })
  await waitFor(() => expect(screen.getByText(/지금은 녹음과 미리 듣기를/)).toBeVisible())
  expect(fetch).toHaveBeenCalledTimes(1)
})
