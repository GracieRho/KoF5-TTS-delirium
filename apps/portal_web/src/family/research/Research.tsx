import { useEffect, useRef, useState } from 'react'
import { WorkspaceShell } from '../../shared/components/WorkspaceShell'
import { Panel } from '../../shared/components/Panel'
import { Select } from '../../shared/components/Select'
import { StatusMessage } from '../../shared/components/StatusMessage'
import {
  CONDITION_LABELS, STRATEGY_LABELS, researchRequest,
  type Answer, type Catalog, type Condition, type Interview, type Preview, type Strategy
} from './api'
import './research.css'

const STYLE_LABELS: Record<string, string> = {
  neutral: '중립 호칭', familiar: '친근한 호칭', polite: '존댓말', casual: '편한 말투',
  acknowledge: '감정 먼저 받아주기', plain: '간결한 표현'
}
const ACTION_LABELS: Record<string, string> = {
  answer: '근거로 답변', abstain: '확인된 정보 없음', identity: 'AI 정체성 안내',
  stop: '대화 중단', refer: '담당자 확인'
}

export function Research() {
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [catalogError, setCatalogError] = useState('')
  const [catalogVersion, setCatalogVersion] = useState(0)
  const [consent, setConsent] = useState(false)
  const [strategy, setStrategy] = useState<Strategy>('adaptive')
  const [budget, setBudget] = useState(5)
  const [answers, setAnswers] = useState<Answer[]>([])
  const [interview, setInterview] = useState<Interview | null>(null)
  const [interviewBusy, setInterviewBusy] = useState(false)
  const [interviewError, setInterviewError] = useState('')
  const [caseId, setCaseId] = useState('')
  const [previews, setPreviews] = useState<{ condition: Condition; result: Preview }[]>([])
  const [previewBusy, setPreviewBusy] = useState(false)
  const [previewError, setPreviewError] = useState('')
  const [notice, setNotice] = useState('')
  const generation = useRef(0)
  const previewGeneration = useRef(0)
  const interviewController = useRef<AbortController | null>(null)
  const previewController = useRef<AbortController | null>(null)
  const questionShownAt = useRef(0)
  const timings = useRef<number[]>([])
  const exportUrl = useRef<string | null>(null)
  const questionHeading = useRef<HTMLLegendElement | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    let current = true
    setCatalogError('')
    researchRequest<Catalog>('/catalog', controller.signal).then(data => {
      if (!current) return
      if (!Array.isArray(data.cases) || !data.cases.length || !Array.isArray(data.strategies)
        || !data.strategies.includes('adaptive') || !Array.isArray(data.conditions) || !data.conditions.length
        || !Number.isInteger(data.default_budget) || data.default_budget < 1 || data.default_budget > 8) {
        throw new Error('연구 질문과 사례 구성을 확인해주세요.')
      }
      setCatalog(data)
      setBudget(data.default_budget)
      setCaseId(data.cases[0].id)
    }).catch(error => {
      if (current && !controller.signal.aborted) setCatalogError(error instanceof Error ? error.message : '연구 서버에 연결할 수 없습니다.')
    })
    return () => { current = false; controller.abort() }
  }, [catalogVersion])

  useEffect(() => () => {
    generation.current++
    previewGeneration.current++
    interviewController.current?.abort()
    previewController.current?.abort()
    if (exportUrl.current) URL.revokeObjectURL(exportUrl.current)
  }, [])

  useEffect(() => { questionHeading.current?.focus() }, [interview?.next_question?.id])

  function clearResults() {
    generation.current++
    previewGeneration.current++
    interviewController.current?.abort()
    previewController.current?.abort()
    setAnswers([])
    setInterview(null)
    setInterviewBusy(false)
    setInterviewError('')
    setPreviews([])
    setPreviewBusy(false)
    setPreviewError('')
    setNotice('')
    timings.current = []
    if (exportUrl.current) { URL.revokeObjectURL(exportUrl.current); exportUrl.current = null }
  }

  async function requestInterview(nextAnswers: Answer[], elapsed?: number) {
    if (!consent || !catalog || interviewBusy) return
    interviewController.current?.abort()
    previewGeneration.current++
    previewController.current?.abort()
    setPreviewBusy(false)
    setPreviews([])
    const controller = new AbortController()
    interviewController.current = controller
    const epoch = ++generation.current
    setInterviewBusy(true)
    setInterviewError('')
    try {
      const result = await researchRequest<Interview>('/interview', controller.signal, {
        answers: nextAnswers, strategy, seed: 0, budget
      })
      if (generation.current !== epoch || controller.signal.aborted) return
      if (!Number.isFinite(result.uncertainty) || !Array.isArray(result.heldout_predictions)
        || typeof result.done !== 'boolean' || !result.predicted_style
        || (result.next_question !== null && (!result.next_question?.id || !Array.isArray(result.next_question.options)))) {
        throw new Error('질문 응답 형식이 올바르지 않습니다. 다시 시작해주세요.')
      }
      setInterview(result)
      setAnswers(nextAnswers)
      setPreviews([])
      if (elapsed !== undefined) timings.current.push(Math.round(elapsed))
      questionShownAt.current = performance.now()
    } catch (error) {
      if (generation.current === epoch && !controller.signal.aborted) {
        setInterviewError(error instanceof Error ? error.message : '질문을 불러오지 못했습니다.')
      }
    } finally {
      if (generation.current === epoch) setInterviewBusy(false)
    }
  }

  async function compare() {
    if (!catalog || !consent || !caseId || previewBusy || interviewBusy) return
    previewController.current?.abort()
    const controller = new AbortController()
    previewController.current = controller
    const epoch = ++previewGeneration.current
    setPreviewBusy(true)
    setPreviewError('')
    setPreviews([])
    try {
      const results = await Promise.all(catalog.conditions.map(async condition => ({
        condition,
        result: await researchRequest<Preview>('/preview', controller.signal, {
          case_id: caseId, condition, ...(interview ? { style: interview.predicted_style } : {})
        })
      })))
      if (previewGeneration.current !== epoch || controller.signal.aborted) return
      if (results.some(({ result }) => typeof result.text !== 'string' || !Array.isArray(result.evidence_ids) || !Array.isArray(result.claims))) {
        throw new Error('비교 응답 형식이 올바르지 않습니다. 다시 비교해주세요.')
      }
      setPreviews(results)
    } catch (error) {
      if (previewGeneration.current === epoch && !controller.signal.aborted) {
        setPreviewError(error instanceof Error ? error.message : '근거 비교를 불러오지 못했습니다.')
      }
    } finally {
      if (previewGeneration.current === epoch) setPreviewBusy(false)
    }
  }

  function exportResults() {
    if (!interview) return
    if (exportUrl.current) URL.revokeObjectURL(exportUrl.current)
    const blob = new Blob([JSON.stringify({
      schema: 'favilium-research-ui/v1', synthetic: true, created_at: new Date().toISOString(),
      strategy, seed: 0, budget, answers, response_time_ms: timings.current,
      interview, case_id: caseId, comparisons: previews,
      method: '구조화 선택과 제한된 표현. 실제 참여자·LLM·음성·임상 평가 결과가 아님.'
    }, null, 2)], { type: 'application/json' })
    exportUrl.current = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = exportUrl.current
    link.download = 'favilium-research.json'
    document.body.append(link)
    link.click()
    link.remove()
    const url = exportUrl.current
    window.setTimeout(() => {
      URL.revokeObjectURL(url)
      if (exportUrl.current === url) exportUrl.current = null
    }, 0)
    setNotice('현재 화면의 선택과 비교 결과를 JSON으로 내보냈습니다.')
  }

  const selectedCase = catalog?.cases.find(item => item.id === caseId)
  return <WorkspaceShell area="보호자" homeHref="/research" title="개인화 연구" current="질문과 근거"
    navigation={<><a href="#research-interview">질문 인터뷰</a><a href="#research-evidence">근거 비교</a></>}>
    <div className="research-workspace">
      <div className="research-heading">
        <h1>표현을 고르는 질문</h1>
        <div className="research-actions">
          <button type="button" onClick={exportResults} disabled={!interview || interviewBusy || previewBusy}>결과 내보내기</button>
          <button type="button" onClick={() => { clearResults(); setConsent(false) }}>모두 초기화</button>
        </div>
      </div>
      {!catalog && !catalogError && <p role="status">연구 질문과 사례를 불러오고 있습니다…</p>}
      {catalogError && <section className="research-blocker" role="alert">
        <h2>연구 서버 연결을 확인해주세요</h2><p>{catalogError}</p>
        <button type="button" onClick={() => setCatalogVersion(version => version + 1)}>다시 연결</button>
      </section>}
      {catalog && <>
        <section id="research-interview" className="research-section">
          <Panel title="질문 인터뷰" description="같은 질문 예산에서 고정·무작위·적응형 질문을 비교합니다. 선택 기록은 화면 메모리에만 있으며 새로고침하면 지워집니다.">
            <div className="research-settings">
              <Select label="질문 선택 방식" value={strategy} onValueChange={value => { clearResults(); setStrategy(value as Strategy) }}>
                {catalog.strategies.map(value => <option key={value} value={value}>{STRATEGY_LABELS[value]}</option>)}
              </Select>
              <Select label="질문 예산" value={String(budget)} onValueChange={value => { clearResults(); setBudget(Number(value)) }}>
                {Array.from({ length: catalog.default_budget }, (_, index) => index + 1).map(value => <option key={value} value={value}>{value}개</option>)}
              </Select>
            </div>
            <label className="research-consent"><input type="checkbox" checked={consent} onChange={event => { clearResults(); setConsent(event.target.checked) }} />
              <span>가상 예시로 진행하며 실제 환자에게 사용하지 않습니다.</span>
            </label>
            <p className="research-boundary">AI 개인화 연구를 위한 구조화된 선택과 표현입니다. 실제 가족 통화·치료 효과·개인의 인격 복제를 뜻하지 않습니다.</p>
            {!interview && <button type="button" className="primary" disabled={!consent || interviewBusy} onClick={() => void requestInterview([])}>{interviewBusy ? '질문을 준비하고 있습니다…' : '질문 시작'}</button>}
            {interviewError && <p role="alert" className="research-error">{interviewError} 현재 선택은 유지됩니다. 다시 시도해주세요.</p>}
            {interview && <>
              <div className="research-progress"><span>선택한 질문 {interview.answered_count} / {interview.budget}</span><progress max={interview.budget} value={interview.answered_count} aria-label="인터뷰 진행" /></div>
              {interview.next_question && <fieldset className="research-question" disabled={interviewBusy}>
                <legend ref={questionHeading} tabIndex={-1}>{interview.next_question.scenario}</legend>
                <div className="research-options">{interview.next_question.options.map((option, index) => <button type="button" key={option.id} onClick={() => void requestInterview([...answers, { question_id: interview.next_question!.id, option_id: option.id }], performance.now() - questionShownAt.current)}>
                  <span aria-hidden="true">{String(index + 1).padStart(2, '0')}</span>{option.text}
                </button>)}</div>
              </fieldset>}
              {interviewBusy && <p role="status">선택을 반영해 다음 질문을 계산하고 있습니다…</p>}
              <dl className="research-summary"><div><dt>현재 표현 예측</dt><dd>{Object.values(interview.predicted_style).map(value => STYLE_LABELS[value] ?? value).join(' · ')}</dd></div><div><dt>가설 불확실성</dt><dd>{Math.round(interview.uncertainty * 100)}%<small>가설 모델의 엔트로피이며 실제 예측 정확도가 아닙니다.</small></dd></div></dl>
              {interview.done && <section className="research-heldout"><h3>인터뷰에 쓰지 않은 상황의 예측</h3><p>정답이나 실제 보호자의 응답이 아닌, 현재 선택에서 계산한 예측입니다.</p>
                {interview.heldout_predictions.map(item => <article key={item.question_id}><h4>{item.scenario}</h4><p>{item.text}</p></article>)}
              </section>}
            </>}
          </Panel>
        </section>
        <section id="research-evidence" className="research-section">
          <Panel title="같은 상황, 다른 근거 처리" description="동일한 가상 사실을 네 방법에 제공합니다. 말투만 제한적으로 덧붙이고, 선택한 근거와 답변 여부를 비교합니다. 규칙 기반 추출 비교이며 강한 LLM baseline 성능 평가가 아닙니다. 자유 생성 LLM이나 실제 음성을 호출하지 않습니다.">
            <div className="research-compare-controls"><Select label="가상 가족과 상황" value={caseId} onValueChange={value => { previewGeneration.current++; previewController.current?.abort(); setPreviewBusy(false); setPreviews([]); setPreviewError(''); setCaseId(value) }}>
              {catalog.cases.map(item => <option key={item.id} value={item.id}>{item.profile_id} · {item.description ?? item.question}</option>)}
            </Select><button type="button" disabled={!consent || previewBusy || interviewBusy} onClick={() => void compare()}>{previewBusy ? '비교하고 있습니다…' : '네 방법 비교'}</button></div>
            {selectedCase && <p className="research-scenario">{selectedCase.question}</p>}
            {!consent && <p className="research-boundary">가상 예시 사용 확인 후 비교할 수 있습니다.</p>}
            {previewError && <p role="alert" className="research-error">{previewError}</p>}
            {!!previews.length && <div className="research-comparisons">{previews.map(({ condition, result }) => <article key={condition}>
              <h3>{CONDITION_LABELS[condition]}</h3><p className="research-action">{ACTION_LABELS[result.action] ?? result.action}</p><p>{result.text}</p>
              <dl><div><dt>사용 근거</dt><dd>{result.evidence_ids.length ? result.evidence_ids.join(', ') : '없음'}</dd></div><div><dt>사실 문구</dt><dd>{result.claims.length ? result.claims.join(' / ') : '없음'}</dd></div></dl>
            </article>)}</div>}
          </Panel>
        </section>
      </>}
      <StatusMessage>{notice}</StatusMessage>
    </div>
  </WorkspaceShell>
}
