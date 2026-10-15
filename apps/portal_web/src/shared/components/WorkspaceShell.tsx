import type { ReactNode } from 'react'
import { AppHeader } from './AppHeader'
import { Icon } from './Icon'

type Props = {
  area: '보호자' | '병원'
  title: string
  subtitle: string
  current: string
  status?: string
  note?: ReactNode
  navigation: ReactNode
  children: ReactNode
  homeHref?: string
}

export function WorkspaceShell({
  area,
  title,
  subtitle,
  current,
  status,
  note,
  navigation,
  children,
  homeHref
}: Props) {
  return (
    <div className="workspace-shell">
      <AppHeader area={area} homeHref={homeHref} />
      <aside className="studio-nav">
        <div className="studio-space">
          <div>
            <strong>{title}</strong>
            <span>{subtitle}</span>
          </div>
        </div>
        <nav aria-label={`${title} 메뉴`}>{navigation}</nav>
        {note && (
          <div className="studio-nav-bottom">
            <Icon name="shield" size={18} />
            <span>{note}</span>
          </div>
        )}
      </aside>
      <main className="studio-workspace">
        <header className="studio-topbar">
          <span>
            {title}
            <span className="breadcrumb-separator">/</span>
            {current}
          </span>
          {status && <span className="workspace-status">{status}</span>}
        </header>
        <div className="studio-content">{children}</div>
        <footer className="studio-footer">
          <span>Familiar Voice</span>
          <span>기억을 소중히, 목소리를 따뜻하게.</span>
        </footer>
      </main>
    </div>
  )
}
