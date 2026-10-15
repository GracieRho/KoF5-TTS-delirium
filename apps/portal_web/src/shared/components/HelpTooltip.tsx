import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { useAnchoredLayer } from '../hooks/useAnchoredLayer'

export function HelpTooltip({ label = '도움말', children }: { label?: string; children: ReactNode }) {
  const id = useId(), root = useRef<HTMLSpanElement>(null), trigger = useRef<HTMLButtonElement>(null)
  const focused = useRef(false)
  const [open, setOpen] = useState(false), [pinned, setPinned] = useState(false)
  const { layer, position } = useAnchoredLayer(open, trigger, 290)
  function close() { setOpen(false); setPinned(false) }
  useEffect(() => {
    if (!open) return
    function outside(event: PointerEvent) { if (!root.current?.contains(event.target as Node)) close() }
    function escape(event: KeyboardEvent) { if (event.key === 'Escape') { event.stopPropagation(); close() } }
    document.addEventListener('pointerdown', outside)
    document.addEventListener('keydown', escape, true)
    return () => { document.removeEventListener('pointerdown', outside); document.removeEventListener('keydown', escape, true) }
  }, [open])
  return <span className="help-tooltip" ref={root} onMouseEnter={() => setOpen(true)} onMouseLeave={() => { if (!pinned && !focused.current) setOpen(false) }}>
    <button ref={trigger} type="button" className="help-trigger" aria-label={label} aria-expanded={open} aria-controls={id} aria-describedby={open ? id : undefined}
      onFocus={() => { focused.current = true; setOpen(true) }} onBlur={() => { focused.current = false; if (!pinned) setOpen(false) }} onClick={() => { setPinned(!pinned); setOpen(!pinned) }}>?</button>
    <div ref={layer} id={id} role="tooltip" popover="manual" hidden={!open} className="help-content" style={position}>{children}</div>
  </span>
}
