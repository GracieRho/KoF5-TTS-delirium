import type { ReactNode } from 'react'
import { AppHeader } from './AppHeader'
import { Icon } from './Icon'

export function WorkspaceShell({ children, research = false, actions }: { children: ReactNode; research?: boolean; actions?: ReactNode }) {
  const space = research ? '연구자 공간' : '보호자 음성 스튜디오'
  const page = research ? '연구 음성 보관함' : '목소리 작업실'
  return (
    <div className={'workspace-shell ' + (research ? 'research-theme' : 'family-theme')}>
      <AppHeader research={research} />
      <aside className="studio-nav">
        <div className="studio-space"><strong>{space}</strong></div>
        <nav aria-label={space + ' 메뉴'}>
          <a aria-current="page" href={research ? window.location.pathname + window.location.hash : '#workspace'}><Icon name={research ? 'memory' : 'voice'} />{page}</a>
        </nav>
      </aside>
      <main id="workspace" className="studio-workspace">
        <header className="studio-topbar">
          <span>{space}<span className="breadcrumb-separator">/</span>{page}</span>
          {actions}
        </header>
        <div className="studio-content">{children}</div>
      </main>
    </div>
  )
}
