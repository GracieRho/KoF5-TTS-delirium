export function StatusMessage({ children, tone = 'info' }: { children?: React.ReactNode; tone?: 'info' | 'success' | 'warning' | 'danger' }) {
  if (!children) return null
  return <div className={`status status-${tone}`} role="status" aria-live="polite">{children}</div>
}
