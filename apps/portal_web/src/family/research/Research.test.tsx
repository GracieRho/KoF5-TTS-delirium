import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Research } from './Research'
import { App } from '../../App'
import type { Catalog, Interview, Preview } from './api'

vi.mock('../../shared/auth/AuthContext', () => ({ useAuth: () => { throw new Error('연구 화면에 로그인 연결이 실행되면 안 됩니다.') } }))

const catalog: Catalog = {
  cases: [
    { id: 'c1', profile_id: '가상 가족 A', question: '오늘 누가 오나요?' },
    { id: 'c2', profile_id: '가상 가족 B', question: '좋아하는 음식은 무엇인가요?' }
  ],
  strategies: ['fixed', 'random', 'adaptive'],
  conditions: ['full_context', 'rag', 'no_time', 'proposed'], default_budget: 5
}
const first: Interview = {
  next_question: { id: 'q1', scenario: '낯선 장소가 불안하다고 해요.', options: [{ id: 'o1', text: '먼저 마음을 받아줘요.' }, { id: 'o2', text: '주변 상황부터 설명해요.' }] },
  answered_count: 0, budget: 5, done: false,
  predicted_style: { address: 'neutral', ending: 'polite', support: 'plain' }, uncertainty: 1, heldout_predictions: []
}
const finished: Interview = {
  ...first, next_question: null, answered_count: 5, done: true,
  predicted_style: { address: 'familiar', ending: 'polite', support: 'acknowledge' }, uncertainty: 0.3,
  heldout_predictions: [{ question_id: 'h1', scenario: '미관측 상황이에요.', option_id: 'a', text: '예측한 표현이에요.' }]
}
const preview: Preview = { action: 'abstain', text: '방문 정보가 확인되지 않았어요.', evidence_ids: [], claims: [], reason: 'unknown' }
const response = (value: unknown, ok = true) => ({ ok, json: async () => value })
function prepare() {
  const fetch = vi.fn().mockResolvedValue(response(catalog))
  vi.stubGlobal('fetch', fetch)
  return fetch
}
async function start(fetch: ReturnType<typeof vi.fn>, value = first) {
  await screen.findByRole('button', { name: '질문 시작' })
  fireEvent.click(screen.getByRole('checkbox'))
  fetch.mockResolvedValue(response(value))
  fireEvent.click(screen.getByRole('button', { name: '질문 시작' }))
  await screen.findByText(value.next_question?.scenario ?? '인터뷰에 쓰지 않은 상황의 예측')
}

beforeEach(() => { window.history.replaceState(null, '', '/research') })
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe('개인화 연구', () => {
  it('연구 route는 로그인 없이 catalog를 확인하고 가상 예시 확인 전에는 시작하지 않는다', async () => {
    const fetch = prepare()
    render(<App />)
    expect(await screen.findByRole('button', { name: '질문 시작' })).toBeDisabled()
    expect(screen.getByRole('button', { name: '네 방법 비교' })).toBeDisabled()
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(fetch.mock.calls[0][0]).toBe('/research-api/catalog')
    expect(screen.queryByText('방문 정보가 확인되지 않았어요.')).not.toBeInTheDocument()
  })

  it('서버가 비활성이면 오류를 보여주며 재연결 전 가짜 결과를 표시하지 않는다', async () => {
    const fetch = prepare().mockResolvedValueOnce(response({ detail: '연구 기능이 비활성 상태입니다.' }, false))
    render(<Research />)
    expect(await screen.findByRole('alert')).toHaveTextContent('연구 기능이 비활성 상태입니다.')
    expect(screen.queryByRole('button', { name: '질문 시작' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '다시 연결' }))
    expect(await screen.findByRole('button', { name: '질문 시작' })).toBeDisabled()
    expect(fetch).toHaveBeenCalledTimes(2)
  })

  it('선택을 기록한 뒤 heldout 예측과 동일한 표현 설정으로 네 방법을 비교한다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    fetch.mockResolvedValue(response(finished))
    fireEvent.click(screen.getByRole('button', { name: /먼저 마음을 받아줘요/ }))
    expect(await screen.findByText('예측한 표현이에요.')).toBeInTheDocument()
    expect(JSON.parse(fetch.mock.calls[2][1].body)).toEqual({ answers: [{ question_id: 'q1', option_id: 'o1' }], strategy: 'adaptive', seed: 0, budget: 5 })
    fetch.mockResolvedValue(response(preview))
    fireEvent.click(screen.getByRole('button', { name: '네 방법 비교' }))
    expect(await screen.findAllByText(preview.text)).toHaveLength(4)
    const calls = fetch.mock.calls.filter(([url]) => url === '/research-api/preview')
    expect(calls.map(([, init]) => JSON.parse(init.body).condition)).toEqual(catalog.conditions)
    expect(calls.every(([, init]) => JSON.parse(init.body).style.support === 'acknowledge')).toBe(true)
  })

  it('요청 실패 후 기존 질문과 선택 기록을 유지해 다시 선택할 수 있다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    fetch.mockRejectedValueOnce(new Error('연결이 끊겼습니다.'))
    fireEvent.click(screen.getByRole('button', { name: /먼저 마음을 받아줘요/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('연결이 끊겼습니다.')
    expect(screen.getByText(first.next_question!.scenario)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /먼저 마음을 받아줘요/ })).toBeEnabled()
  })

  it('모두 초기화하면 늦게 도착한 인터뷰 응답을 버린다', async () => {
    const fetch = prepare()
    render(<Research />)
    await screen.findByRole('button', { name: '질문 시작' })
    fireEvent.click(screen.getByRole('checkbox'))
    let finish!: (value: unknown) => void
    fetch.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    fireEvent.click(screen.getByRole('button', { name: '질문 시작' }))
    fireEvent.click(screen.getByRole('button', { name: '모두 초기화' }))
    await act(async () => { finish(response(first)) })
    expect(screen.queryByText(first.next_question!.scenario)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: '질문 시작' })).toBeDisabled()
    expect(screen.getByRole('button', { name: '결과 내보내기' })).toBeDisabled()
  })

  it('인터뷰 응답을 바꾸면 이전 표현으로 계산 중인 비교를 버린다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    let finish!: (value: unknown) => void
    fetch.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    fetch.mockResolvedValue(response(preview))
    fireEvent.click(screen.getByRole('button', { name: '네 방법 비교' }))
    fetch.mockResolvedValue(response(finished))
    fireEvent.click(screen.getByRole('button', { name: /먼저 마음을 받아줘요/ }))
    await screen.findByText('예측한 표현이에요.')
    await act(async () => { finish(response(preview)) })
    expect(screen.queryByText(preview.text)).not.toBeInTheDocument()
  })

  it('명시적으로 JSON을 내보내고 Blob URL을 해제하며 초기화하면 결과를 지운다', async () => {
    const fetch = prepare()
    const create = vi.fn((_blob: Blob) => 'blob:research')
    const revoke = vi.fn()
    vi.stubGlobal('URL', { createObjectURL: create, revokeObjectURL: revoke })
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => undefined)
    render(<Research />)
    await start(fetch, finished)
    fireEvent.click(screen.getByRole('button', { name: '결과 내보내기' }))
    expect(create).toHaveBeenCalledTimes(1)
    expect(create.mock.calls[0][0]).toBeInstanceOf(Blob)
    expect(click).toHaveBeenCalledTimes(1)
    await waitFor(() => expect(revoke).toHaveBeenCalledWith('blob:research'))
    fireEvent.click(screen.getByRole('button', { name: '모두 초기화' }))
    expect(screen.queryByText('예측한 표현이에요.')).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: '결과 내보내기' })).toBeDisabled())
  })
})
