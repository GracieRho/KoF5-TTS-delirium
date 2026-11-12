import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import Research from './Research'

const link = 'a'.repeat(43)
const reference = '000000000000000000000001'
const recorded = '2026-11-12T00:00:00Z'

afterEach(() => {
  window.history.replaceState(null, '', '/')
  vi.unstubAllGlobals()
})

it('opens the public blue workspace without showing an email gate or requesting private records', () => {
  window.history.replaceState(null, '', '/research')
  const fetch = vi.fn()
  vi.stubGlobal('fetch', fetch)
  const { container } = render(<Research />)
  expect(screen.getByRole('heading', { name: '연구 음성 보관함' })).toBeVisible()
  expect(screen.getByRole('heading', { name: '안내 문장 예시' })).toBeVisible()
  expect(container.querySelector('.research-theme')).not.toBeNull()
  expect(screen.queryByRole('textbox', { name: /이메일/ })).toBeNull()
  expect(fetch).not.toHaveBeenCalled()
})

it.each(['view', 'manage'])('opens the real archive from a %s link, without user input', async scope => {
  window.history.replaceState(null, '', '/research#access=' + link)
  const fetch = vi.fn(async (url: string, init?: RequestInit) => {
    if (url === '/api/research/session' && init?.method === 'POST') return Response.json({ scope })
    const items = url.startsWith('/api/research/voices?') ? [{
      reference, state: 'ready', updated_at: recorded, consented_at: recorded, has_sample: true, speech_count: 0,
    }] : []
    return Response.json({ items, has_more: false })
  })
  vi.stubGlobal('fetch', fetch)
  render(<Research />)
  fireEvent.click(await screen.findByRole('button', { name: new RegExp(reference) }))
  expect(screen.getByLabelText('보호자 원본 녹음')).toBeVisible()
  expect(fetch).toHaveBeenCalledWith('/api/research/session', expect.objectContaining({
    method: 'POST', headers: { Authorization: 'Bearer ' + link },
  }))
  if (scope === 'view') {
    expect(screen.queryByText('이 목소리로 새 안내 문장 만들기')).toBeNull()
    expect(screen.queryByRole('button', { name: '목소리와 자료 삭제' })).toBeNull()
  } else {
    expect(screen.getByText('이 목소리로 새 안내 문장 만들기')).toBeVisible()
    expect(screen.getByRole('button', { name: '목소리와 자료 삭제' })).toBeVisible()
  }
})

it('shows the example when a link has been replaced', async () => {
  window.history.replaceState(null, '', '/research#access=' + link)
  const fetch = vi.fn().mockResolvedValue(Response.json({ detail: '유효한 연구팀 링크를 다시 열어 주세요.' }, { status: 403 }))
  vi.stubGlobal('fetch', fetch)
  render(<Research />)
  expect(await screen.findByRole('alert')).toHaveTextContent('유효한 연구팀 링크')
  expect(screen.getByRole('heading', { name: '안내 문장 예시' })).toBeVisible()
  expect(fetch).toHaveBeenCalledTimes(1)
})
