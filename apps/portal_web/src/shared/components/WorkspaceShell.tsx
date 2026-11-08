import type { ReactNode } from 'react'
import { AppHeader } from './AppHeader'
import { Icon } from './Icon'

export function WorkspaceShell({ actions, children }: { actions?: ReactNode; children: ReactNode }) {
  return (
    <div className="workspace-shell family-theme">
      <AppHeader />
      <aside className="studio-nav">
        <div className="studio-space"><strong>보호자 음성 스튜디오</strong></div>
        <nav aria-label="보호자 음성 스튜디오 메뉴">
          <a aria-current="page" href="#workspace"><Icon name="voice" />목소리 작업실</a>
        </nav>
      </aside>
      <main id="workspace" className="studio-workspace">
        <header className="studio-topbar">
          <span>보호자 음성 스튜디오<span className="breadcrumb-separator">/</span>목소리 작업실</span>
          {actions}
        </header>
        <div className="studio-content">{children}</div>
      </main>
    </div>
  )
}
