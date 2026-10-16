import { HelpTooltip } from './HelpTooltip'
import { useEffect, useId, useRef, type ReactNode } from 'react'

export function ResponsiveSheet({ open, title, onClose, children, help }: { help?: ReactNode; open: boolean; title: string; onClose: () => void; children: ReactNode }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const returnFocus = useRef<HTMLElement | null>(null)
  const titleId = useId()

  useEffect(() => {
    const element = dialog.current
    if (!element) return
    if (open && !element.open) {
      returnFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
      element.showModal()
    } else if (!open && element.open) {
      element.close()
      returnFocus.current?.focus()
    }
  }, [open])

  return <dialog ref={dialog} className="responsive-sheet" aria-labelledby={titleId} onCancel={event => { event.preventDefault(); onClose() }}>
    <div className="sheet-frame">
      <header className="sheet-header"><div className="heading-with-help"><h2 id={titleId}>{title}</h2>{help && <HelpTooltip label={`${title} 도움말`}>{help}</HelpTooltip>}</div><button type="button" aria-label={`${title} 닫기`} onClick={onClose}>닫기</button></header>
      <div className="sheet-body">{open ? children : null}</div>
    </div>
  </dialog>
}
