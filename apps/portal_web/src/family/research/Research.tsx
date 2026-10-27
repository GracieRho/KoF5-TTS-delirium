import { useEffect, useRef, useState } from 'react'
import { profileReady } from '../studio/readiness'
import { studioRequest, SPEECH_STYLE_LABELS, type Profile, type StudioState } from '../studio/api'
import { FamilyNavigation } from '../components/FamilyNavigation'
import { WorkspaceShell } from '../../shared/components/WorkspaceShell'
import { Panel } from '../../shared/components/Panel'
import { Select } from '../../shared/components/Select'
import { StatusMessage } from '../../shared/components/StatusMessage'
import {
  CONDITION_LABELS, STRATEGY_LABELS, researchRequest,
  type Answer, type Catalog, type Condition, type Interview, type Preview, type Strategy, type WrittenResult, type Interpretation
} from './api'
import './research.css'

const STYLE_LABELS: Record<string, string> = {
  acknowledge: '마음 먼저 짚기', plain: '내용부터 이야기하기',
  ask: '뜻을 물어보기', offer: '먼저 제안하기', brief: '짧게 말하기', elaborate: '구체적으로 설명하기'
}
const ACTION_LABELS: Record<string, string> = {
  answer: '사용 가능한 정보로 답변', abstain: '추가 확인 필요', identity: 'AI임을 안내',
  stop: '대화 중단', refer: '담당자 확인'
}

export function Research() {
  const [tab, setTab] = useState<'interview' | 'answers'>('interview')
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [catalogError, setCatalogError] = useState('')
  const [catalogVersion, setCatalogVersion] = useState(0)
  const [consent, setConsent] = useState(false)
  const [strategy, setStrategy] = useState<Strategy>('adaptive')
  const [budget, setBudget] = useState(8)
  const [family, setFamily] = useState<StudioState | null>(null)
  const [speechStyle, setSpeechStyle] = useState('')
  const [profileBusy, setProfileBusy] = useState(false)
  const [profileError, setProfileError] = useState('')
  const [draft, setDraft] = useState('')
  const [referenceOption, setReferenceOption] = useState('')
  const [selectedModel, setSelectedModel] = useState('')
  const [providerConsent, setProviderConsent] = useState(false)
  const [interpretations, setInterpretations] = useState<(Interpretation & { question_id: string })[]>([])
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
    Promise.all([researchRequest<Catalog>('/catalog', controller.signal), studioRequest<StudioState>('/state')]).then(([data, savedFamily]) => {
      if (!current) return
      if (!Array.isArray(data.cases) || !data.cases.length || !Array.isArray(data.strategies)
        || !data.strategies.includes('adaptive') || !Array.isArray(data.conditions) || !data.conditions.length
        || !Number.isInteger(data.default_budget) || data.default_budget < 8 || data.default_budget > 12
        || typeof data.direct_input?.available !== 'boolean' || typeof data.direct_input?.model !== 'string'
        || !Array.isArray(data.direct_input.models) || !data.direct_input.models.some(item => item.id === data.direct_input.model)
        || !Number.isInteger(data.max_budget) || data.max_budget < data.default_budget || data.max_budget > 12) {
        throw new Error('질문과 상황 목록을 확인해주세요.')
      }
      if (!savedFamily?.profile || !Array.isArray(savedFamily.memories)) throw new Error('저장된 가족 자료 형식을 확인해주세요.')
      setSelectedModel(data.direct_input.model)
      setFamily(savedFamily)
      setCatalog(data)
      setBudget(data.default_budget)
      setCaseId(data.cases[0].id)
    }).catch(error => {
      if (current && !controller.signal.aborted) setCatalogError(error instanceof Error ? error.message : '질문을 불러올 수 없습니다.')
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
    setDraft('')
    setReferenceOption('')
    setInterpretations([])
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

  async function requestInterview(nextAnswers: Answer[], elapsed?: number, writtenText?: string) {
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
      let result: Interview
      let recordedAnswers = nextAnswers
      let interpreted: WrittenResult | null = null
      if (writtenText !== undefined) {
        interpreted = await researchRequest<WrittenResult>('/interpret', controller.signal, {
          answers: nextAnswers, strategy, seed: 0, budget, text: writtenText, provider_processing_consent: providerConsent, model: selectedModel
        })
        if (!interpreted.answer || interpreted.answer.text !== writtenText || !interpreted.interpretation
          || interpreted.interpretation.cost !== 0 || typeof interpreted.interpretation.reason !== 'string'
          || !Array.isArray(interpreted.interpretation.attempts) || interpreted.interpretation.attempts.length < 1 || interpreted.interpretation.attempts.length > 3) {
          throw new Error('직접 입력 해석 결과를 확인하지 못했습니다.')
        }
        result = interpreted.interview
        recordedAnswers = [...nextAnswers, interpreted.answer]
      } else {
        result = await researchRequest<Interview>('/interview', controller.signal, {
          answers: nextAnswers, strategy, seed: 0, budget
        })
      }
      if (generation.current !== epoch || controller.signal.aborted) return
      if (!Number.isFinite(result.uncertainty) || !Array.isArray(result.heldout_predictions)
        || typeof result.done !== 'boolean' || !result.predicted_style
        || !Number.isInteger(result.reflected_count) || !Array.isArray(result.written_answers)
        || (result.next_question !== null && (!result.next_question?.id || !Array.isArray(result.next_question.options)))) {
        throw new Error('질문 응답 형식이 올바르지 않습니다. 다시 시작해주세요.')
      }
      setDraft('')
      setReferenceOption('')
      setInterview(result)
      setAnswers(recordedAnswers)
      const written = recordedAnswers.at(-1)
      if (interpreted) {
        setInterpretations(items => [...items, { ...interpreted!.interpretation, question_id: interpreted!.answer.question_id }])
        setNotice(interpreted.interpretation.option_id ? '입력한 문장을 해석해 말투 예측에 반영했습니다.' : '원문을 기록했습니다. 해석이 모호해 말투 예측에는 반영하지 않았습니다.')
      } else if (written?.text) setNotice(written.option_id ? '직접 쓴 답변과 지정한 말투를 반영했습니다.' : '직접 쓴 답변을 기록했습니다. 말투는 자동 분류하지 않았습니다.')
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
          case_id: caseId, condition
        })
      })))
      if (previewGeneration.current !== epoch || controller.signal.aborted) return
      if (results.some(({ result }) => typeof result.text !== 'string' || !Array.isArray(result.evidence_ids) || !Array.isArray(result.claims))) {
        throw new Error('비교 응답 형식이 올바르지 않습니다. 다시 비교해주세요.')
      }
      setPreviews(results)
    } catch (error) {
      if (previewGeneration.current === epoch && !controller.signal.aborted) {
        setPreviewError(error instanceof Error ? error.message : '예상 답변을 불러오지 못했습니다.')
      }
    } finally {
      if (previewGeneration.current === epoch) setPreviewBusy(false)
    }
  }

  function exportResults() {
    if (!interview) return
    if (exportUrl.current) URL.revokeObjectURL(exportUrl.current)
    const blob = new Blob([JSON.stringify({
      schema: 'favilium-research-ui/v2', data_kind: 'user-authored-interview-with-synthetic-preview', created_at: new Date().toISOString(),
      strategy, seed: 0, budget, answers, response_time_ms: timings.current,
      interview, address_as: family?.profile.address_as, address_aliases: family?.profile.address_aliases,
      speech_style: family?.profile.speech_style, selected_model: selectedModel, interpretations, case_id: caseId, comparisons: previews,
      method: '선택·직접 입력 인터뷰. 명시적으로 동의한 입력만 무료 모델로 해석. 음성·임상 효과 평가는 아님.'
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

  const usableMemories = family?.memories.filter(memory => memory.category !== 'avoid') ?? []
  const hasProfile = Boolean(family && profileReady(family.profile))
  const hasSpeechStyle = Boolean(family?.profile.speech_style && family.profile.speech_style in SPEECH_STYLE_LABELS)
  const onlySpeechStyleMissing = hasProfile && usableMemories.length > 0 && !hasSpeechStyle
  const prepared = hasProfile && hasSpeechStyle && usableMemories.length > 0
  async function saveSpeechStyle() {
    if (!family || !onlySpeechStyleMissing || !speechStyle || profileBusy) return
    setProfileBusy(true)
    setProfileError('')
    try {
      const saved = await studioRequest<StudioState>('/profile', 'PUT', { ...family.profile, speech_style: speechStyle as Profile['speech_style'] })
      setFamily(saved)
    } catch (error) {
      setProfileError(error instanceof Error ? error.message : '말투를 저장하지 못했어요. 다시 시도해주세요.')
    } finally { setProfileBusy(false) }
  }
  function expression(item: { text: string; casual_text: string; mixed_text: string }) {
    const text = family?.profile.speech_style === 'casual' ? item.casual_text
      : family?.profile.speech_style === 'mixed' ? item.mixed_text : item.text
    return contextualize(text)
  }
  function contextualize(text: string) {
    return text.replaceAll('{address}', family?.profile.address_as ?? '')
      .replaceAll('{memory_title}', usableMemories[0]?.title ?? '')
  }
  const selectedCase = catalog?.cases.find(item => item.id === caseId)
  const proposed = previews.find(item => item.condition === 'proposed')?.result
  return <WorkspaceShell area="보호자" homeHref="/studio" title="가족의 공간" current="대화 맞춤"
    navigation={<FamilyNavigation current="personalize" />}>
    <div className="research-workspace">
      <div className="research-heading">
        <h1>대화 맞춤</h1>
        <div className="research-actions">
          <button type="button" onClick={exportResults} disabled={!interview || interviewBusy || previewBusy}>결과 내보내기</button>
          <button type="button" onClick={() => { clearResults(); setConsent(false); setProviderConsent(false) }}>다시 시작</button>
        </div>
      </div>
      <div className="tabs" role="tablist" aria-label="대화 맞춤">
        {(['interview', 'answers'] as const).map((key, index, keys) => <button key={key}
          id={`personalize-tab-${key}`} role="tab" aria-selected={tab === key}
          aria-controls={`personalize-panel-${key}`} tabIndex={tab === key ? 0 : -1}
          onClick={() => setTab(key)} onKeyDown={event => {
            if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
            event.preventDefault()
            const next = event.key === 'Home' ? keys[0] : event.key === 'End' ? keys[keys.length - 1]
              : keys[(index + (event.key === 'ArrowRight' ? 1 : -1) + keys.length) % keys.length]
            setTab(next)
            document.getElementById(`personalize-tab-${next}`)?.focus()
          }}>{key === 'interview' ? '말투 인터뷰' : '답변 확인'}</button>)}
      </div>
      {!interview && <p className="research-boundary">AI 대화에 사용할 표현을 살펴봅니다. 실제 가족의 답변이나 의료 조언을 대신하지 않습니다.</p>}
      {!catalog && !catalogError && <p role="status">저장된 가족 자료와 질문을 확인하고 있어요…</p>}
      {catalogError && <section className="research-blocker" role="alert">
        <h2>대화 맞춤을 불러오지 못했어요</h2><p>{catalogError}</p>
        <button type="button" onClick={() => setCatalogVersion(version => version + 1)}>다시 연결</button><a href="/studio?tab=memory">가족의 기억으로 이동</a>
      </section>}
      {catalog && !prepared && <Panel title={onlySpeechStyleMissing ? '평소 말투만 알려주세요' : '인터뷰 전에 확인해주세요'}>
        {onlySpeechStyleMissing ? <>
          <p>저장된 호칭 ‘{family!.profile.address_as}’과 대화에 쓸 기억 {usableMemories.length}개를 불러왔어요. 평소 말투를 고르면 바로 시작할 수 있어요.</p>
          <form className="research-setup" onSubmit={event => { event.preventDefault(); void saveSpeechStyle() }}>
            <Select label="평소 말투" required disabled={profileBusy} value={speechStyle} onValueChange={setSpeechStyle}>
              <option value="" disabled>말투를 골라주세요</option>
              {Object.entries(SPEECH_STYLE_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </Select>
            {profileError && <p role="alert" className="research-error">{profileError}</p>}
            <button className="primary" disabled={!speechStyle || profileBusy}>{profileBusy ? '저장하고 있어요…' : '말투 저장하고 계속'}</button>
          </form>
        </> : <>
          <p>인터뷰에 필요한 내용 중 아래 항목만 추가해주세요.</p>
          <ul>{!hasProfile && <li>가족 소개와 주로 부르는 호칭</li>}
            {!hasSpeechStyle && <li>평소 말투</li>}
            {!usableMemories.length && <li>대화에 쓸 가족 기억 1개 이상 (피해야 할 이야기 제외)</li>}</ul>
          <div className="research-setup-actions">
            <a className="button primary" href="/studio?tab=memory">부족한 내용 입력하기</a>
            <button type="button" onClick={() => setCatalogVersion(version => version + 1)}>저장한 내용 새로고침</button>
          </div>
        </>}
      </Panel>}
      {catalog && prepared && <>
        <section id="personalize-panel-interview" role="tabpanel" aria-labelledby="personalize-tab-interview" hidden={tab !== 'interview'}>
          <Panel title={interview?.done ? '선택한 말투로 이렇게 답할 수 있어요' : interview ? '말투 인터뷰' : '인터뷰를 시작할까요?'} className={interview?.next_question ? 'research-interview-active' : ''}>
            {!interview && <>
              <p className="research-intro">가족에게 건넬 말을 직접 쓰거나 네 가지 예시에서 고릅니다. 기본 {budget}개 질문에 답해보세요.</p>
              <div className="research-family-context"><span>{[family!.profile.address_as, ...(family!.profile.address_aliases ?? [])].join(' · ')} / {SPEECH_STYLE_LABELS[family!.profile.speech_style!]}</span><a href="/studio?tab=memory">호칭·말투 수정</a></div>
              <details className="research-details">
                <summary>질문 설정 · {budget}개</summary>
                <div className="research-settings">
                  <Select label="질문 선택 방식" value={strategy} onValueChange={value => { clearResults(); setStrategy(value as Strategy) }}>
                    {catalog.strategies.map(value => <option key={value} value={value}>{STRATEGY_LABELS[value]}</option>)}
                  </Select>
                  <Select label="질문 수" value={String(budget)} onValueChange={value => { clearResults(); setBudget(Number(value)) }}>
                    {Array.from({ length: catalog.max_budget - catalog.default_budget + 1 }, (_, index) => index + catalog.default_budget).map(value => <option key={value} value={value}>{value}개</option>)}
                  </Select>
                  <Select label="먼저 사용할 무료 모델" value={selectedModel} onValueChange={setSelectedModel} disabled={!catalog.direct_input.available}>
                    {catalog.direct_input.models.map(model => <option key={model.id} value={model.id}>{model.name}</option>)}
                  </Select>
                </div>
                <p>기본은 응답에 맞춘 질문입니다. 무료 모델은 직접 입력을 해석할 때만 사용하며, 전송 전 별도로 동의합니다.</p>
              </details>
              <label className="research-consent"><input type="checkbox" checked={consent} onChange={event => { clearResults(); setConsent(event.target.checked) }} />
                <span>가상 상황으로 답하며 실제 환자 정보는 입력하지 않습니다.</span>
              </label>
              <button type="button" className="primary" disabled={!consent || interviewBusy} onClick={() => void requestInterview([])}>{interviewBusy ? '질문을 준비하고 있어요…' : '질문 시작'}</button>
            </>}
            {interviewError && <p role="alert" className="research-error">{interviewError} 현재 선택은 유지됩니다. 다시 시도해주세요.</p>}
            {interview && <>
              <div className="research-progress"><span>{interview.done ? `${interview.budget}개 응답 완료` : `질문 ${interview.answered_count + 1} / ${interview.budget}`}</span><progress max={interview.budget} value={interview.answered_count} aria-label="인터뷰 진행" /></div>
              {interview.next_question && <fieldset className="research-question" disabled={interviewBusy}>
                <legend ref={questionHeading} tabIndex={-1}>{contextualize(interview.next_question.scenario)}</legend>
                <div className="research-options">{interview.next_question.options.map(option => <button type="button" key={option.id} onClick={() => void requestInterview([...answers, { question_id: interview.next_question!.id, option_id: option.id }], performance.now() - questionShownAt.current)}>
                  {expression(option)}
                </button>)}</div>
                  <form className="research-written" onSubmit={event => {
                    event.preventDefault()
                    if (draft.trim() && providerConsent) void requestInterview(answers, performance.now() - questionShownAt.current, draft.trim())
                  }}>
                    <input aria-label="가족에게 건넬 말" type="text" maxLength={500} value={draft} required placeholder="내 말투로 직접 쓰기"
                      onChange={event => { setDraft(event.target.value); setReferenceOption('') }} />
                    {!!draft.trim() && <>
                    <div className="research-input-meta"><span>{draft.length} / 500</span></div>
                    <label className="research-provider-consent"><input type="checkbox" checked={providerConsent} disabled={!catalog.direct_input.available}
                      onChange={event => { setProviderConsent(event.target.checked); setReferenceOption('') }} />
                      <span>AI 해석을 위해 입력 문장을 전송합니다. 공급자가 보관·학습에 사용할 수 있어요.</span>
                    </label>
                    <details className="research-details"><summary>전송·보관 안내</summary>
                      <p>동의하면 입력한 문장과 질문·예시 표현을 OpenRouter 무료 모델로 보냅니다. 저장된 가족 소개·기억 전체는 보내지 않아요. 공급자가 입력을 보관하거나 학습에 사용할 수 있습니다.</p>
                      <p>먼저 사용할 모델: {catalog.direct_input.models.find(model => model.id === selectedModel)?.name}. 실패하면 다른 무료 모델로 바꿔 처음 호출과 대체 호출을 합쳐 최대 3회 시도합니다. 모두 실패하면 입력을 유지하고 오류를 표시합니다.</p>
                    </details>
                    {!catalog.direct_input.available && <p className="research-boundary">무료 모델 키가 연결되지 않았어요. 원문을 기록하거나 예시를 고를 수 있습니다.</p>}
                    {!providerConsent && <details className="research-details"><summary>가까운 표현을 직접 지정하기</summary>
                      <Select label="쓴 문장과 가까운 표현 (선택)" value={referenceOption} onValueChange={setReferenceOption}>
                        <option value="">원문만 기록하기</option>
                        {interview.next_question.options.map((option, index) => <option key={option.id} value={option.id}>{index + 1}. {expression(option)}</option>)}
                      </Select>
                      <p className="research-boundary">가까운 표현을 지정한 경우에만 말투 예측에 반영해요. 원문 기록만으로는 문장의 의미를 분석하지 않습니다.</p>
                    </details>}
                    <div className="research-answer-actions">
                      <button type="button" disabled={!draft.trim() || interviewBusy} onClick={() => void requestInterview([...answers, {
                        question_id: interview.next_question!.id, text: draft.trim(), ...(referenceOption ? { option_id: referenceOption } : {})
                      }], performance.now() - questionShownAt.current)}>{referenceOption ? '지정한 표현으로 계속' : '원문만 기록'}</button>
                      <button type="submit" className="primary" disabled={!draft.trim() || !providerConsent || interviewBusy}>{interviewBusy ? '해석하고 있어요…' : '해석하고 다음'}</button>
                    </div>
                    </>}
                  </form>
              </fieldset>}
              {interviewBusy && <p role="status">선택을 반영하고 있어요…</p>}
              {!!interpretations.length && <details className="research-details"><summary>이전 답변의 해석</summary>
                <p className="research-boundary" role="status">방금 입력한 답변의 해석: {interpretations[interpretations.length - 1].reason}</p>
                <details className="research-details"><summary>모델 시도 내역 ({interpretations[interpretations.length - 1].attempts.length}회)</summary>
                  <ol>{interpretations[interpretations.length - 1].attempts.map(attempt => <li key={attempt.model}>{catalog.direct_input.models.find(model => model.id === attempt.model)?.name ?? attempt.model} · {attempt.status === 'success' ? '성공' : '실패'}</li>)}</ol>
                </details>
              </details>}
              {interview.done && <>
                {interview.reflected_count > 0 && <p className="research-style">예측에 반영한 응답 {interview.reflected_count}개 · {Object.values(interview.predicted_style).map(value => STYLE_LABELS[value] ?? value).join(' · ')}</p>}
                {interview.written_answers.length > 0 && <section className="research-heldout"><h3>내가 쓴 답변</h3>{interview.written_answers.map(item => <article key={item.question_id}><h4>{contextualize(item.scenario)}</h4><p>{item.text}</p><small>{item.reflected ? '말투 예측에 반영함' : '원문 기록 · 말투 미분류'}</small></article>)}</section>}
                {interview.reflected_count > 0 ? <section className="research-heldout"><h3>다른 상황에서는</h3><p>인터뷰에 없던 상황의 예상 표현입니다. 본인의 실제 답변과 다를 수 있어요.</p>
                  {interview.heldout_predictions.map(item => <article key={item.question_id}><h4>{contextualize(item.scenario)}</h4><p>{expression(item)}</p></article>)}
                </section> : <p>말투를 지정한 응답이 없어 다른 상황의 표현은 아직 예상하지 않았어요.</p>}
                <button type="button" className="primary" onClick={() => { setTab('answers'); document.getElementById('personalize-tab-answers')?.focus() }}>상황별 답변 확인</button>
              </>}
              {interview.done && interview.reflected_count > 0 && <details className="research-details"><summary>예측 계산 상세</summary>
                <p>현재 예상 말투: {Object.values(interview.predicted_style).map(value => STYLE_LABELS[value] ?? value).join(' · ')}</p>
                <p>가설 불확실성 {Math.round(interview.uncertainty * 100)}%. 작은 가설 모형의 엔트로피로, 실제 예측 정확도가 아닙니다.</p>
              </details>}
            </>}
            <p className="research-footnote">응답은 이 화면에만 남습니다. 새로고침하거나 다른 메뉴로 나가면 지워집니다.</p>
          </Panel>
        </section>
        <section id="personalize-panel-answers" role="tabpanel" aria-labelledby="personalize-tab-answers" hidden={tab !== 'answers'}>
          <Panel title="이 상황에 어떻게 답할까요?">
            <p className="research-intro">저장한 가족 자료와 별개인 가상 일정 예시입니다. 만료되거나 서로 다른 정보를 답변에서 어떻게 제외하는지 확인합니다.</p>
            {!consent && <label className="research-consent"><input type="checkbox" checked={consent} onChange={event => setConsent(event.target.checked)} />
              <span>가상 상황으로 답하며 실제 환자 정보는 입력하지 않습니다.</span>
            </label>}
            <div className="research-compare-controls"><Select label="확인할 상황" value={caseId} onValueChange={value => { previewGeneration.current++; previewController.current?.abort(); setPreviewBusy(false); setPreviews([]); setPreviewError(''); setCaseId(value) }}>
              {catalog.cases.map(item => <option key={item.id} value={item.id}>{item.description ?? item.question}</option>)}
            </Select><button type="button" className="primary" disabled={!consent || previewBusy || interviewBusy} onClick={() => void compare()}>{previewBusy ? '확인하고 있어요…' : '답변 확인하기'}</button></div>
            {selectedCase && <p className="research-scenario">“{selectedCase.question}”</p>}
            {previewError && <p role="alert" className="research-error">{previewError}</p>}
            {proposed && <>
              <article className="research-reply" aria-label="예상 답변">
                <h3>예상 답변</h3><p>{proposed.text}</p><p className="research-action">{ACTION_LABELS[proposed.action] ?? proposed.action}</p>
                {proposed.claims.length > 0 && <div className="research-facts"><h4>답변에 사용한 내용</h4><ul>{proposed.claims.map((claim, index) => <li key={index}>{claim}</li>)}</ul></div>}
              </article>
              <details className="research-details"><summary>다른 처리 방식과 비교</summary>
                <p>같은 가상 정보를 사용하는 네 규칙의 비교입니다. 실제 LLM 성능 평가가 아닙니다. 위 답변은 출처·유효기간·철회·상충을 확인하는 규칙으로 구성했습니다.</p>
                <div className="research-comparisons">{previews.map(({ condition, result }) => <article key={condition}>
                  <h3>{CONDITION_LABELS[condition]}</h3><p>{result.text}</p>
                  <p className="research-action">{ACTION_LABELS[result.action] ?? result.action}</p>
                  <dl><div><dt>사용한 정보 ID</dt><dd>{result.evidence_ids.length ? result.evidence_ids.join(', ') : '없음'}</dd></div></dl>
                </article>)}</div>
              </details>
            </>}
            <p className="research-footnote">정해진 가상 정보와 문장 규칙으로 구성한 예시입니다. 음성이나 자유로운 AI 답변을 생성하지 않습니다.</p>
          </Panel>
        </section>
      </>}
      <StatusMessage>{notice}</StatusMessage>
    </div>
  </WorkspaceShell>
}
