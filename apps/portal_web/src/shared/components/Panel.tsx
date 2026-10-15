import { HelpTooltip } from './HelpTooltip'
import type { ReactNode } from 'react'
export function Panel({ title, description, actions, children, className = '' }: { title: string; description?: string; actions?: ReactNode; children: ReactNode; className?: string }) {
  return <section className={`panel ${className}`}><div className="panel-heading"><div className="panel-title"><div className="heading-with-help"><h2>{title}</h2>{description && <HelpTooltip label={`${title} 도움말`}>{description}</HelpTooltip>}</div></div>{actions && <div className="panel-actions">{actions}</div>}</div>{children}</section>
}
