import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Research } from './Research'
import { App } from '../../App'
import type { StudioState } from '../studio/api'
import type { Catalog, Interview, Preview } from './api'
import { isPersonalizationPage } from '../components/FamilyNavigation'

vi.mock('../../shared/auth/AuthContext', () => ({ useAuth: () => { throw new Error('연구 화면에 로그인 연결이 실행되면 안 됩니다.') } }))

const catalog: Catalog = {
  cases: [
    { id: 'c1', profile_id: '가상 가족 A', question: '오늘 누가 오나요?' },
    { id: 'c2', profile_id: '가상 가족 B', question: '좋아하는 음식은 무엇인가요?' }
  ],
  strategies: ['fixed', 'random', 'adaptive'],
  direct_input: { available: true, model: 'nvidia/nemotron-3-ultra-550b-a55b:free', models: [{ id: 'nvidia/nemotron-3-ultra-550b-a55b:free', name: 'Nemotron 3 Ultra' }, { id: 'google/gemma-4-31b-it:free', name: 'Gemma 4 31B' }] },
  conditions: ['full_context', 'rag', 'no_time', 'proposed'], default_budget: 8, max_budget: 12
}
const first: Interview = {
  next_question: { id: 'q1', scenario: '낯선 장소가 불안하다고 해요.', options: [
    { id: 'o1', text: '먼저 마음을 받아줘요.', casual_text: '마음부터 받아주자.', mixed_text: '마음부터 받아주자. 같이 살펴봐요.' },
    { id: 'o2', text: '주변 상황부터 설명해요.', casual_text: '상황부터 설명하자.', mixed_text: '상황부터 설명하자. 같이 봐요.' },
    { id: 'o3', text: '어떤 점이 낯선지 물어봐요.', casual_text: '어떤 점이 낯설어?', mixed_text: '어떤 점이 낯설어? 말해줘요.' },
    { id: 'o4', text: '함께 주변을 둘러봐요.', casual_text: '같이 둘러보자.', mixed_text: '같이 둘러보자. 천천히 봐요.' }
  ] },
  answered_count: 0, budget: 8, done: false, reflected_count: 0, written_answers: [],
  predicted_style: { initiative: 'ask', detail: 'brief', support: 'plain' }, uncertainty: 1, heldout_predictions: []
}
const finished: Interview = {
  ...first, next_question: null, answered_count: 8, done: true, reflected_count: 8,
  predicted_style: { initiative: 'offer', detail: 'elaborate', support: 'acknowledge' }, uncertainty: 0.3,
  heldout_predictions: [{ question_id: 'h1', scenario: '미관측 상황이에요.', option_id: 'a', text: '예측한 표현이에요.', casual_text: '예측한 말이야.', mixed_text: '예측한 말이야. 확인해봐요.' }]
}
const preview: Preview = { action: 'abstain', text: '방문 정보가 확인되지 않았어요.', evidence_ids: [], claims: [], reason: 'unknown' }
const family: StudioState = {
  profile: { guardian_name: '가상 보호자', patient_alias: '가상 가족', relationship: '딸', address_as: '아빠', address_aliases: ['아버지'], speech_style: 'polite' },
  memories: [{ id: 'm1', title: '바닷가 산책', category: 'story', content: '함께 산책한 가상 기억', created_at: '2026-10-27T00:00:00Z' }],
  voice: { status: 'none' }, providers: { voice: false, conversation: false, transcription: false }
}
const response = (value: unknown, ok = true) => ({ ok, json: async () => value })
function prepare(savedFamily = family) {
  const fetch = vi.fn().mockImplementation(async (url: string) => response(url === '/local-studio/state' ? savedFamily : catalog))
  vi.stubGlobal('fetch', fetch)
  return fetch
}
async function start(fetch: ReturnType<typeof vi.fn>, value = first) {
  await screen.findByRole('button', { name: '질문 시작' })
  fireEvent.click(screen.getByRole('checkbox', { name: '가상 상황으로 답하며 실제 환자 정보는 입력하지 않습니다.' }))
  fetch.mockResolvedValue(response(value))
  fireEvent.click(screen.getByRole('button', { name: '질문 시작' }))
  await screen.findByText(value.next_question?.scenario ?? '다른 상황에서는')
}

beforeEach(() => { window.history.replaceState(null, '', '/research') })
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe('대화 맞춤', () => {
  it('선택 모델을 먼저 요청하고 세 번 실패하면 입력과 질문을 유지한다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    fireEvent.change(screen.getByLabelText('내 말로 직접 답하기'), { target: { value: '천천히 다시 골라보자.' } })
    fireEvent.click(screen.getByRole('checkbox', { name: /입력한 문장과 질문/ }))
    fireEvent.click(screen.getByRole('combobox', { name: '먼저 사용할 무료 모델' }))
    fireEvent.click(screen.getByRole('option', { name: 'Gemma 4 31B' }))
    const attempts = ['google/gemma-4-31b-it:free', 'nvidia/nemotron-3-ultra-550b-a55b:free', 'google/gemma-4-26b-a4b-it:free'].map(model => ({ model, status: 'failed', error: '공급자 오류' }))
    fetch.mockResolvedValue(response({ detail: { message: '무료 모델 분석이 3번 실패했습니다.', attempts } }, false))
    fireEvent.click(screen.getByRole('button', { name: 'AI로 해석하고 계속' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('3번 실패')
    expect(screen.getByRole('alert')).toHaveTextContent('시도한 모델:')
    expect(screen.getByLabelText('내 말로 직접 답하기')).toHaveValue('천천히 다시 골라보자.')
    expect(screen.getByText(first.next_question!.scenario)).toBeInTheDocument()
    const calls = fetch.mock.calls.filter(([url]) => url === '/research-api/interpret')
    expect(calls).toHaveLength(1)
    expect(JSON.parse(calls[0][1].body).model).toBe('google/gemma-4-31b-it:free')
  })

  it('명시적 동의 후에만 무료 모델 해석을 요청하고 결과를 반영한다', async () => {
    const fetch = prepare()
    sessionStorage.setItem('favilium.session', 'synthetic-session')
    render(<Research />)
    await start(fetch)
    fireEvent.change(screen.getByLabelText('내 말로 직접 답하기'), { target: { value: '천천히 바꿔도 돼. 같이 다시 골라보자.' } })
    expect(fetch.mock.calls.filter(([url]) => url === '/research-api/interpret')).toHaveLength(0)
    fireEvent.click(screen.getByRole('checkbox', { name: /입력한 문장과 질문/ }))
    fetch.mockResolvedValue(response({ answer: { question_id: 'q1', text: '천천히 바꿔도 돼. 같이 다시 골라보자.', option_id: 'o1' },
      interview: { ...finished, written_answers: [{ question_id: 'q1', scenario: first.next_question!.scenario, text: '천천히 바꿔도 돼. 같이 다시 골라보자.', reflected: true }] },
      interpretation: { option_id: 'o1', reason: '마음을 받아주고 다시 고를 여유를 줍니다.', model: 'fixed-free-model', cost: 0, attempts: [{ model: 'fixed-free-model', status: 'success' }] } }))
    fireEvent.click(screen.getByRole('button', { name: 'AI로 해석하고 계속' }))
    expect(await screen.findByRole('heading', { name: '내가 쓴 답변' })).toBeInTheDocument()
    const calls = fetch.mock.calls.filter(([url]) => url === '/research-api/interpret')
    expect(calls).toHaveLength(1)
    expect(JSON.parse(calls[0][1].body)).toMatchObject({ text: '천천히 바꿔도 돼. 같이 다시 골라보자.', provider_processing_consent: true, answers: [] })
    expect(calls[0][1].headers.Authorization).toBe('Bearer synthetic-session')
    expect(calls[0][1].headers['X-Kof5-Studio']).toBe('1')
    expect(screen.getByText(/방금 입력한 답변의 해석: 마음을 받아주고/)).toBeInTheDocument()
    sessionStorage.clear()
  })

  it('저장 자료가 비었거나 피해야 할 기억만 있으면 먼저 가족의 기억으로 안내한다', async () => {
    prepare({ ...family, profile: { ...family.profile, speech_style: undefined }, memories: [{ ...family.memories[0], category: 'avoid' }] })
    render(<Research />)
    expect(await screen.findByRole('heading', { name: '인터뷰 전에 확인해주세요' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '부족한 내용 입력하기' })).toHaveAttribute('href', '/studio?tab=memory')
    expect(screen.queryByRole('button', { name: '질문 시작' })).not.toBeInTheDocument()
  })

  it('기억과 호칭이 있으면 말투만 이 화면에서 저장하고 나머지 자료를 보존한다', async () => {
    const fetch = prepare({ ...family, profile: { ...family.profile, speech_style: undefined } })
    render(<Research />)
    expect(await screen.findByRole('heading', { name: '평소 말투만 알려주세요' })).toBeInTheDocument()
    expect(screen.getByText(/대화에 쓸 기억 1개/)).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: '부족한 내용 입력하기' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: '말투 저장하고 계속' })).toBeDisabled()
    fireEvent.click(screen.getByRole('combobox', { name: '평소 말투' }))
    fireEvent.click(screen.getByRole('option', { name: '반존대' }))
    fetch.mockResolvedValueOnce(response({ detail: '저장 연결 실패' }, false))
    fireEvent.click(screen.getByRole('button', { name: '말투 저장하고 계속' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('저장 연결 실패')
    expect(screen.queryByRole('button', { name: '질문 시작' })).not.toBeInTheDocument()
    fetch.mockResolvedValueOnce(response({ ...family, profile: { ...family.profile, speech_style: 'mixed' } }))
    fireEvent.click(screen.getByRole('button', { name: '말투 저장하고 계속' }))
    expect(await screen.findByRole('button', { name: '질문 시작' })).toBeInTheDocument()
    const save = fetch.mock.calls.find(([url]) => url === '/local-studio/profile')!
    expect(save[1].method).toBe('PUT')
    expect(JSON.parse(save[1].body)).toEqual({ ...family.profile, speech_style: 'mixed' })
    expect(fetch.mock.calls.some(([url]) => url.includes('/memories'))).toBe(false)
  })

  it('저장 자료 조회 실패를 빈 자료로 간주하지 않는다', async () => {
    prepare().mockImplementation(async (url: string) => {
      if (url === '/local-studio/state') throw new Error('보호자 로그인이 필요합니다.')
      return response(catalog)
    })
    render(<Research />)
    expect(await screen.findByRole('alert')).toHaveTextContent('보호자 로그인이 필요합니다.')
    expect(screen.queryByRole('heading', { name: '인터뷰 전에 확인해주세요' })).not.toBeInTheDocument()
  })

  it('저장된 반말 설정을 모든 선택지에 공통 적용하고 네 표현을 제공한다', async () => {
    const fetch = prepare({ ...family, profile: { ...family.profile, speech_style: 'casual' } })
    render(<Research />)
    await start(fetch)
    expect(screen.getByRole('button', { name: '마음부터 받아주자.' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '상황부터 설명하자.' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '어떤 점이 낯설어?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '같이 둘러보자.' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '먼저 마음을 받아줘요.' })).not.toBeInTheDocument()
  })

  it('직접 입력한 답변을 임의 분류하지 않고 원문을 전송하며 실패하면 초안을 유지한다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    fireEvent.change(screen.getByLabelText('내 말로 직접 답하기'), { target: { value: '아빠, 나랑 한 바퀴 돌아볼까?' } })
    fetch.mockRejectedValueOnce(new Error('연결 실패'))
    fireEvent.click(screen.getByRole('button', { name: '내 답변으로 계속' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('연결 실패')
    expect(screen.getByLabelText('내 말로 직접 답하기')).toHaveValue('아빠, 나랑 한 바퀴 돌아볼까?')
    const result: Interview = { ...finished, reflected_count: 0, written_answers: [{ question_id: 'q1', scenario: first.next_question!.scenario, text: '아빠, 나랑 한 바퀴 돌아볼까?', reflected: false }] }
    fetch.mockResolvedValue(response(result))
    fireEvent.click(screen.getByRole('button', { name: '내 답변으로 계속' }))
    await screen.findByRole('heading', { name: '내가 쓴 답변' })
    expect(screen.getByText('아빠, 나랑 한 바퀴 돌아볼까?')).toBeInTheDocument()
    const request = JSON.parse(fetch.mock.calls.at(-1)![1].body)
    expect(request.answers).toEqual([{ question_id: 'q1', text: '아빠, 나랑 한 바퀴 돌아볼까?' }])
    expect(screen.queryByText('예측한 표현이에요.')).not.toBeInTheDocument()
    expect(screen.getByText('말투를 지정한 응답이 없어 다른 상황의 표현은 아직 예상하지 않았어요.')).toBeInTheDocument()
  })

  it('인증 예외는 합성 대화 맞춤 주소에만 적용한다', () => {
    for (const path of ['/studio', '/studio?tab=voice', '/studio?tab=personalizex', '/hospital?tab=personalize']) {
      window.history.replaceState(null, '', path)
      expect(isPersonalizationPage()).toBe(false)
    }
    for (const path of ['/research', '/research/', '/studio?tab=personalize']) {
      window.history.replaceState(null, '', path)
      expect(isPersonalizationPage()).toBe(true)
    }
  })

  it('홈 메뉴와 브랜드는 홈으로 연결되고 본문 탭은 서로 분리되며 키보드로 이동한다', async () => {
    prepare()
    render(<Research />)
    await screen.findByRole('button', { name: '질문 시작' })
    expect(screen.getByRole('link', { name: '함께 시작하기' })).toHaveAttribute('href', '/studio')
    expect(screen.getByRole('link', { name: 'Favilium' })).toHaveAttribute('href', '/studio')
    expect(screen.getByRole('link', { name: '대화 맞춤' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('tabpanel')).toHaveAccessibleName('말투 인터뷰')
    expect(screen.queryByRole('button', { name: '답변 확인하기' })).not.toBeInTheDocument()
    fireEvent.keyDown(screen.getByRole('tab', { name: '말투 인터뷰' }), { key: 'ArrowRight' })
    expect(screen.getByRole('tab', { name: '답변 확인' })).toHaveFocus()
    expect(screen.getByRole('tabpanel')).toHaveAccessibleName('답변 확인')
    expect(screen.queryByRole('button', { name: '질문 시작' })).not.toBeInTheDocument()
    fireEvent.keyDown(screen.getByRole('tab', { name: '답변 확인' }), { key: 'Home' })
    expect(screen.getByRole('tab', { name: '말투 인터뷰' })).toHaveFocus()
  })

  it('홈의 대화 맞춤 주소도 인증이나 보호자 자료 요청 없이 같은 화면을 연다', async () => {
    window.history.replaceState(null, '', '/studio?tab=personalize')
    const fetch = prepare()
    render(<App />)
    expect(await screen.findByRole('button', { name: '질문 시작' })).toBeDisabled()
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls[0][0]).toBe('/research-api/catalog')
  })

  it('연구 route는 로그인 없이 catalog를 확인하고 가상 예시 확인 전에는 시작하지 않는다', async () => {
    const fetch = prepare()
    render(<App />)
    expect(await screen.findByRole('button', { name: '질문 시작' })).toBeDisabled()
    fireEvent.click(screen.getByRole('tab', { name: '답변 확인' }))
    expect(screen.getByRole('button', { name: '답변 확인하기' })).toBeDisabled()
    expect(fetch).toHaveBeenCalledTimes(2)
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
    expect(fetch).toHaveBeenCalledTimes(4)
  })

  it('선택을 기록한 뒤 heldout 예측과 동일한 표현 설정으로 네 방법을 비교한다', async () => {
    const fetch = prepare()
    render(<Research />)
    await start(fetch)
    fetch.mockResolvedValue(response(finished))
    fireEvent.click(screen.getByRole('button', { name: /먼저 마음을 받아줘요/ }))
    expect(await screen.findByText('예측한 표현이에요.')).toBeInTheDocument()
    expect(JSON.parse(fetch.mock.calls[3][1].body)).toEqual({ answers: [{ question_id: 'q1', option_id: 'o1' }], strategy: 'adaptive', seed: 0, budget: 8 })
    fetch.mockResolvedValue(response(preview))
    fireEvent.click(screen.getByRole('tab', { name: '답변 확인' }))
    fireEvent.click(screen.getByRole('button', { name: '답변 확인하기' }))
    expect(await screen.findByRole('article', { name: '예상 답변' })).toHaveTextContent(preview.text)
    expect(screen.getByText('다른 처리 방식과 비교').closest('details')).not.toHaveAttribute('open')
    fireEvent.click(screen.getByText('다른 처리 방식과 비교'))
    expect(await screen.findAllByText(preview.text)).toHaveLength(5)
    const calls = fetch.mock.calls.filter(([url]) => url === '/research-api/preview')
    expect(calls.map(([, init]) => JSON.parse(init.body).condition)).toEqual(catalog.conditions)
    expect(calls.every(([, init]) => !('style' in JSON.parse(init.body)))).toBe(true)
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
    fireEvent.click(screen.getByRole('checkbox', { name: '가상 상황으로 답하며 실제 환자 정보는 입력하지 않습니다.' }))
    let finish!: (value: unknown) => void
    fetch.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    fireEvent.click(screen.getByRole('button', { name: '질문 시작' }))
    fireEvent.click(screen.getByRole('button', { name: '다시 시작' }))
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
    fireEvent.click(screen.getByRole('tab', { name: '답변 확인' }))
    fireEvent.click(screen.getByRole('button', { name: '답변 확인하기' }))
    fetch.mockResolvedValue(response(finished))
    fireEvent.click(screen.getByRole('tab', { name: '말투 인터뷰' }))
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
    fireEvent.click(screen.getByRole('button', { name: '다시 시작' }))
    expect(screen.queryByText('예측한 표현이에요.')).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: '결과 내보내기' })).toBeDisabled())
  })
})
