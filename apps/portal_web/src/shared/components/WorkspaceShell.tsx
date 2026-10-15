import type { ReactNode } from 'react'
import { AppHeader } from './AppHeader'
import { Icon } from './Icon'

type Props = {
  area: '보호자' | '병원'
  title: string
  current: string
  status?: string
  note?: ReactNode
  navigation: ReactNode
  children: ReactNode
  homeHref?: string
  brandSymbol?: string
}

export function WorkspaceShell({
  area,
  title,
  current,
  status,
  note,
  navigation,
  children,
  homeHref,
  brandSymbol
}: Props) {
  return (
    <div className={`workspace-shell ${area === '병원' ? 'hospital-theme' : 'family-theme'}`}>
      <AppHeader area={area} homeHref={homeHref} brandSymbol={brandSymbol} />
      <aside className="studio-nav">
        <div className="studio-space">
          <div>
            <strong>{title}</strong>
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
      </main>
    </div>
  )
}
