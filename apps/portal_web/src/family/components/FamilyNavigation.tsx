import { Icon } from '../../shared/components/Icon'

export const FAMILY_TABS = {
  home: '함께 시작하기',
  voice: '목소리 등록',
  memory: '가족의 기억',
  personalize: '대화 맞춤',
  chat: '대화해보기',
  linked: '병원 연결'
} as const

export type FamilyTab = keyof typeof FAMILY_TABS

export function isPersonalizationPage() {
  const path = window.location.pathname.replace(/\/$/, '')
  return path === '/research' || (path === '/studio' && new URLSearchParams(window.location.search).get('tab') === 'personalize')
}

export function FamilyNavigation({ current, onNavigate, memoryCount }: {
  current: FamilyTab
  onNavigate?: (tab: Exclude<FamilyTab, 'personalize'>) => void
  memoryCount?: number
}) {
  return <>{(Object.keys(FAMILY_TABS) as FamilyTab[]).map(key => <a
    key={key}
    href={key === 'home' ? '/studio' : `/studio?tab=${key}`}
    aria-current={current === key ? 'page' : undefined}
    onClick={event => {
      if (onNavigate && key !== 'personalize' && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
        event.preventDefault()
        onNavigate(key)
      }
    }}
  >
    <Icon name={key === 'linked' ? 'shield' : key === 'personalize' ? 'patient' : key} />
    {FAMILY_TABS[key]}
    {key === 'memory' && memoryCount !== undefined && <span className="nav-count">{memoryCount}</span>}
  </a>)}</>
}
