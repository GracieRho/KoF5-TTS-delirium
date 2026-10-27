export type Strategy = 'fixed' | 'random' | 'adaptive'
export type Condition = 'full_context' | 'rag' | 'no_time' | 'proposed'
export type Answer = { question_id: string; option_id: string }
export type Question = { id: string; scenario: string; options: { id: string; text: string }[] }
export type ResearchCase = { id: string; profile_id: string; question: string; description?: string }
export type Catalog = {
  cases: ResearchCase[]
  strategies: Strategy[]
  conditions: Condition[]
  default_budget: number
}
export type Interview = {
  next_question: Question | null
  answered_count: number
  budget: number
  done: boolean
  predicted_style: Record<string, string>
  uncertainty: number
  heldout_predictions: { question_id: string; scenario: string; option_id: string; text: string }[]
}
export type Preview = {
  action: string
  text: string
  evidence_ids: string[]
  claims: string[]
  reason: string
}

export const STRATEGY_LABELS: Record<Strategy, string> = {
  fixed: '고정 질문', random: '무작위 질문', adaptive: '적응형 질문'
}
export const CONDITION_LABELS: Record<Condition, string> = {
  full_context: '전체 문맥(첫 근거)', rag: '키워드 검색', no_time: '시간 처리 제외', proposed: '출처·시간 적용'
}

export async function researchRequest<T>(path: '/catalog' | '/interview' | '/preview', signal: AbortSignal, body?: unknown): Promise<T> {
  const response = await fetch(`/research-api${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
    cache: 'no-store',
    credentials: 'omit'
  })
  let data: unknown
  try { data = await response.json() } catch { throw new Error('연구 서버 응답을 읽을 수 없습니다. 연결을 확인해주세요.') }
  if (!response.ok) {
    const detail = data && typeof data === 'object' && 'detail' in data ? data.detail : null
    throw new Error(typeof detail === 'string' ? detail : '연구 요청을 처리하지 못했습니다. 설정과 입력을 확인해주세요.')
  }
  return data as T
}
