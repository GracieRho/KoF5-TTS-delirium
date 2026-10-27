import { HelpTooltip } from '../../shared/components/HelpTooltip'
import { useAuth } from '../../shared/auth/AuthContext'
import { GuardianPortal } from '../guardian/pages/GuardianPortal'
import { useEffect, useRef, useState } from 'react'
import { WorkspaceShell } from '../../shared/components/WorkspaceShell'
import { Icon } from '../../shared/components/Icon'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { FamilyProfile } from './FamilyProfile'
import { MemoryLibrary } from './MemoryLibrary'
import { VoiceEnrollment } from './VoiceEnrollment'
import { Conversation } from './Conversation'
import { conversationReadiness } from './readiness'
import { VoiceWave } from '../components/VoiceWave'
import { studioRequest, type StudioState, type Profile, type MemoryInput } from './api'
import { FAMILY_TABS, FamilyNavigation, type FamilyTab } from '../components/FamilyNavigation'

type Tab = Exclude<FamilyTab, 'personalize'>
export function Studio() {
  const auth = useAuth()
  const [state, setState] = useState<StudioState | null>(null)
  const initialTab = new URLSearchParams(window.location.search).get('tab')
  const [tab, setTabState] = useState<Tab>(initialTab && initialTab !== 'personalize' && initialTab in FAMILY_TABS ? initialTab as Tab : 'home')
  function setTab(next: Tab) {
    setTabState(next)
    const url = new URL(window.location.href)
    if (next === 'home') url.searchParams.delete('tab')
    else url.searchParams.set('tab', next)
    window.history.replaceState(null, '', url)
  }
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState(false)
  const [profileOpen, setProfileOpen] = useState(false)
  const locked = useRef(false)
  const mounted = useRef(true)
  async function refresh() {
    setLoading(true)
    try {
      const next = await studioRequest<StudioState>('/state')
      if (mounted.current) {
        setState(next)
        setError('')
      }
    } catch {
      if (mounted.current)
        setError(
          '서비스에 연결하지 못했습니다. 잠시 후 다시 연결해주세요.'
        )
    } finally {
      if (mounted.current) setLoading(false)
    }
  }
  useEffect(() => {
    mounted.current = true
    void refresh()
    return () => {
      mounted.current = false
    }
  }, [])
  async function mutate(path: string, method: string, data?: unknown): Promise<boolean> {
    if (locked.current) return false
    locked.current = true
    setBusy(true)
    setNotice('')
    try {
      const next = await studioRequest<StudioState>(path, method, data)
      if (mounted.current) {
        setState(next)
        setNotice('변경 내용을 반영했습니다.')
      }
      return true
    } catch (error) {
      if (mounted.current) {
        setNotice(error instanceof Error ? error.message : '작업을 완료하지 못했습니다.')
        try {
          const next = await studioRequest<StudioState>('/state')
          if (mounted.current) setState(next)
        } catch {
          /* Keep the last confirmed state and report the failed operation. */
        }
      }
      return false
    } finally {
      locked.current = false
      if (mounted.current) setBusy(false)
    }
  }
  const readiness = state ? conversationReadiness(state) : null
  const done = readiness?.steps ?? [false, false, false]
  const steps: { title: string; text: string; action: string; tab?: Tab }[] = [
    {
      title: '우리 가족 소개',
      text: '관계와 평소 부르는 호칭을 알려주세요.',
      action: done[0] ? '소개 수정' : '소개 시작'
    },
    {
      title: '익숙한 목소리',
      text: '짧은 녹음 세 개로 목소리를 등록해요.',
      action: done[1] ? '목소리 확인' : '목소리 등록',
      tab: 'voice'
    },
    {
      title: '함께한 기억',
      text: '작은 추억과 좋아하는 이야기를 남겨요.',
      action: done[2] ? '기억 더하기' : '첫 기억 남기기',
      tab: 'memory'
    }
  ]
  return (
    <WorkspaceShell
      area="보호자"
      homeHref="/studio"
      title="가족의 공간"
      current={FAMILY_TABS[tab]}
      navigation={
        <>
          <FamilyNavigation current={tab} onNavigate={setTab} memoryCount={state?.memories.length} />
          <button onClick={auth.signOut}>로그아웃</button>
        </>
      }
    >
      {tab === 'linked' && <GuardianPortal />}
      {tab !== 'linked' && loading && <p role="status">가족의 공간을 준비하고 있어요…</p>}
      {tab !== 'linked' && error && (
        <div className="studio-empty" role="alert">
          <Icon name="shield" size={32} />
          <h1>연결을 확인해주세요</h1>
          <p>{error}</p>
          <button onClick={() => void refresh()}>다시 연결</button>
        </div>
      )}
      {tab !== 'linked' && state && !error && (
        <>
          {tab === 'home' && (
            <>
              <div className="welcome-band">
                <div>
                  <h1>
                    익숙한 목소리,
                    <br />
                    함께한 기억으로.
                  </h1>
                  <button onClick={() => setTab('chat')}>
                    {readiness?.ready ? '대화해보기' : '대화 준비 확인'}
                    <Icon name="arrow" size={18} />
                  </button>
                </div>
                <VoiceWave />
              </div>
              <section className="setup-section">
                <div className="section-heading">
                  <h2>
                    {readiness?.ready ? '대화 준비 완료' : done.every(Boolean) ? '서비스 연결 확인 필요' : '가족 자료 준비'}
                  </h2>
                  <span className="compact">{done.filter(Boolean).length} / 3 준비 완료</span>
                </div>
                <div className="setup-list">
                  {steps.map((step, index) => (
                    <div className="setup-row" key={step.title}>
                      <span className={`step-number ${done[index] ? 'step-done' : ''}`}>
                        {done[index] ? <Icon name="check" size={19} /> : `0${index + 1}`}
                      </span>
                      <div>
                        <div className="heading-with-help"><h3>{step.title}</h3><HelpTooltip label={`${step.title} 도움말`}>{step.text}</HelpTooltip></div>
                      </div>
                      <button
                        onClick={() => {
                          if (step.tab) setTab(step.tab)
                          else setProfileOpen(true)
                        }}
                      >
                        {step.action}
                        <Icon name="arrow" size={16} />
                      </button>
                    </div>
                  ))}
                </div>
              </section>
              <div className="studio-bottom-note"><span>AI 대화</span><HelpTooltip label="AI 대화 안내">가족 목소리로 읽어주는 AI 대화입니다. 실제 가족 통화나 의료 상담을 대신하지 않습니다.</HelpTooltip></div>
            </>
          )}
          {tab === 'memory' && (
            <MemoryLibrary
              profile={state.profile}
              editProfile={() => setProfileOpen(true)}
              memories={state.memories}
              busy={busy}
              save={(data: MemoryInput, id?: string) =>
                mutate(`/memories${id ? `/${id}` : ''}`, id ? 'PUT' : 'POST', data)
              }
              remove={(id) => mutate(`/memories/${id}`, 'DELETE')}
            />
          )}
          {tab === 'voice' && (
            <VoiceEnrollment
              state={state}
              busy={busy}
              enroll={(samples) =>
                mutate('/voice', 'POST', {
                  own_voice_confirmed: true,
                  provider_processing_consent: true,
                  samples_wav_base64: samples
                })
              }
              action={async (method, path) => {
                await mutate(path, method)
              }}
              report={(message) => setNotice(message)}
            />
          )}
          {tab === 'chat' && (
            <Conversation
              state={state}
              report={(message) => setNotice(message)}
              prepare={(target) => target === 'profile' ? setProfileOpen(true) : setTab(target)}
              refresh={() => void refresh()}
            />
          )}
          <ResponsiveSheet
            open={profileOpen}
            help="가상의 가족 정보와 별칭을 사용하세요. 실제 환자 정보나 주민번호·병력은 입력하지 않습니다." title="우리 가족 소개"
            onClose={() => {
              if (!busy) setProfileOpen(false)
            }}
          >
            <FamilyProfile
              profile={state.profile}
              busy={busy}
              onSave={async (profile: Profile) => {
                if (await mutate('/profile', 'PUT', profile)) setProfileOpen(false)
              }}
            />
          </ResponsiveSheet>
        </>
      )}
      <StatusMessage>{notice}</StatusMessage>
    </WorkspaceShell>
  )
}
