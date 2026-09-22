import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'

type Tone = 'info' | 'success' | 'warning' | 'danger'
type Toast = { id: number; content: ReactNode; tone: Tone }
type ShowToast = (content: ReactNode, tone: Tone) => void

const ToastContext = createContext<ShowToast>(() => undefined)

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<Toast | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const sequence = useRef(0)

  const showToast = useCallback<ShowToast>((content, tone) => {
    if (timer.current) clearTimeout(timer.current)
    setToast({ id: ++sequence.current, content, tone })
    timer.current = setTimeout(() => setToast(null), tone === 'danger' ? 7000 : 5000)
  }, [])

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])

  return <ToastContext.Provider value={showToast}>
    {children}
    {toast && <output className={`toast toast-${toast.tone}`} role={toast.tone === 'danger' ? 'alert' : 'status'} aria-live={toast.tone === 'danger' ? 'assertive' : 'polite'}>{toast.content}</output>}
  </ToastContext.Provider>
}

export function StatusMessage({ children, tone = 'info' }: { children?: ReactNode; tone?: Tone }) {
  const showToast = useContext(ToastContext)
  useEffect(() => { if (children) showToast(children, tone) }, [children, showToast, tone])
  return null
}
