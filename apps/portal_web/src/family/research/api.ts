export type Strategy = 'fixed' | 'random' | 'adaptive'
export type Condition = 'full_context' | 'rag' | 'no_time' | 'proposed'
export type Answer = { question_id: string } & ({ option_id: string; text?: string } | { text: string; option_id?: string })
export type Expression = { text: string; casual_text: string; mixed_text: string }
export type Question = { id: string; scenario: string; options: ({ id: string } & Expression)[] }
export type ResearchCase = { id: string; profile_id: string; question: string; description?: string }
export type Catalog = {
  cases: ResearchCase[]
  strategies: Strategy[]
  conditions: Condition[]
  direct_input: { available: boolean; model: string; models: { id: string; name: string }[] }
  max_budget: number
  default_budget: number
}
export type Interview = {
  next_question: Question | null
  answered_count: number
  budget: number
  done: boolean
  predicted_style: Record<string, string>
  uncertainty: number
  reflected_count: number
  written_answers: { question_id: string; scenario: string; text: string; reflected: boolean }[]
  heldout_predictions: { question_id: string; scenario: string; option_id: string; text: string; casual_text: string; mixed_text: string }[]
}
export type ModelAttempt = { model: string; status: 'failed' | 'success'; error?: string }
export type Interpretation = { attempts: ModelAttempt[]; option_id: string | null; reason: string; model: string; cost: number }
export type WrittenResult = { answer: Answer; interview: Interview; interpretation: Interpretation }
export type Preview = {
  action: string
  text: string
  evidence_ids: string[]
  claims: string[]
  reason: string
}

export const STRATEGY_LABELS: Record<Strategy, string> = {
  fixed: '정해진 순서대로', random: '무작위로', adaptive: '응답에 맞춰서'
}
export const CONDITION_LABELS: Record<Condition, string> = {
  full_context: '먼저 등록된 정보 선택', rag: '질문과 비슷한 정보 선택', no_time: '유효기간 확인 생략', proposed: '현재 사용할 수 있는 정보 선택'
}

export async function researchRequest<T>(path: '/catalog' | '/interview' | '/preview' | '/interpret', signal: AbortSignal, body?: unknown): Promise<T> {
  const response = await fetch(`/research-api${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json',
      ...(path === '/interpret' ? { Authorization: `Bearer ${sessionStorage.getItem('favilium.session') ?? ''}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
    cache: 'no-store',
    credentials: 'omit'
  })
  let data: unknown
  try { data = await response.json() } catch { throw new Error('응답을 읽을 수 없습니다. 연결을 확인해주세요.') }
  if (!response.ok) {
    const detail = data && typeof data === 'object' && 'detail' in data ? data.detail : null
    if (detail && typeof detail === 'object' && 'message' in detail && typeof detail.message === 'string') {
      const attempts = 'attempts' in detail && Array.isArray(detail.attempts) ? detail.attempts : []
      const models = attempts.map(item => item && typeof item.model === 'string' ? item.model : '').filter(Boolean)
      throw new Error(detail.message + (models.length ? ` 시도한 모델: ${models.join(' → ')}` : ''))
    }
    throw new Error(typeof detail === 'string' ? detail : '요청을 처리하지 못했습니다. 설정과 입력을 확인해주세요.')
  }
  return data as T
}
