import type { ReactNode } from 'react'
export function Panel({ title, description, actions, children, className = '' }: { title: string; description?: string; actions?: ReactNode; children: ReactNode; className?: string }) {
  return <section className={`panel ${className}`}><div className="panel-heading"><div className="panel-title"><h2>{title}</h2>{description && <p>{description}</p>}</div>{actions && <div className="panel-actions">{actions}</div>}</div>{children}</section>
}
