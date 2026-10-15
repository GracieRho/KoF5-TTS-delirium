import { Children, isValidElement, useEffect, useId, useRef, useState, type ReactNode, type ReactElement } from 'react'
import { HelpTooltip } from './HelpTooltip'
import { useAnchoredLayer } from '../hooks/useAnchoredLayer'

type Props = { label: string; children: ReactNode; value?: string; defaultValue?: string; onValueChange: (value: string) => void; required?: boolean; disabled?: boolean; name?: string; hideLabel?: boolean; help?: ReactNode }
type Option = { value: string; label: ReactNode; disabled?: boolean }
export function Select({ label, children, value, defaultValue, onValueChange, required, disabled, name, hideLabel = false, help }: Props) {
  const options: Option[] = Children.toArray(children).filter(isValidElement).map(child => {
    const props = (child as ReactElement<{ value?: string | number; children: ReactNode; disabled?: boolean }>).props
    return { value: String(props.value ?? props.children ?? ''), label: props.children, disabled: props.disabled }
  })
  const [internal, setInternal] = useState(defaultValue ?? options[0]?.value ?? '')
  const selected = value ?? internal, index = options.findIndex(option => option.value === selected)
  const [open, setOpen] = useState(false), [active, setActive] = useState(Math.max(0, index)), [invalid, setInvalid] = useState(false)
  const id = useId(), root = useRef<HTMLDivElement>(null), trigger = useRef<HTMLButtonElement>(null), search = useRef({ text: '', at: 0 })
  const { layer, position } = useAnchoredLayer(open, trigger)
  function choose(option: Option) {
    if (option.disabled) return
    setInternal(option.value); onValueChange(option.value); setInvalid(false); setOpen(false); trigger.current?.focus()
  }
  function reveal() { setActive(Math.max(0, index)); setOpen(true) }
  useEffect(() => {
    if (!open) return
    function outside(event: PointerEvent) { if (!root.current?.contains(event.target as Node)) setOpen(false) }
    document.addEventListener('pointerdown', outside)
    return () => document.removeEventListener('pointerdown', outside)
  }, [open])
  useEffect(() => { if (disabled || !options.length) setOpen(false) }, [disabled, options.length])
  useEffect(() => { if (open) document.getElementById(`${id}-${active}`)?.scrollIntoView?.({ block: 'nearest' }) }, [open, active, id])
  return <div className="select-field" ref={root}>
    {!hideLabel && <span id={`${id}-label`} className="select-label">{label}{help && <HelpTooltip label={`${label} 도움말`}>{help}</HelpTooltip>}</span>}
    <select className="select-native" aria-hidden="true" tabIndex={-1} name={name} value={selected} required={required} disabled={disabled}
      onChange={event => choose({ value: event.target.value, label: '' })} onInvalid={event => { event.preventDefault(); setInvalid(true); reveal(); trigger.current?.focus() }}>{children}</select>
    <button ref={trigger} type="button" className="select-trigger" role="combobox" aria-label={label} aria-haspopup="listbox" aria-expanded={open} aria-controls={`${id}-list`} aria-activedescendant={open ? `${id}-${active}` : undefined} aria-required={required} aria-invalid={invalid || undefined} disabled={disabled || !options.length}
      onClick={() => open ? setOpen(false) : reveal()} onBlur={event => { if (!root.current?.contains(event.relatedTarget)) setOpen(false) }} onKeyDown={event => {
        if (!options.length) return
        if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
          event.preventDefault()
          const step = event.key === 'ArrowUp' || event.key === 'End' ? -1 : 1
          let next = event.key === 'Home' ? 0 : event.key === 'End' ? options.length - 1 : open ? active + step : Math.max(0, index)
          next = (next + options.length) % options.length
          for (let count = 0; count < options.length && options[next]?.disabled; count++) next = (next + step + options.length) % options.length
          setActive(next); setOpen(true)
        } else if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault(); if (open && options[active]) choose(options[active]); else reveal()
        } else if (event.key === 'Escape' && open) { event.preventDefault(); event.stopPropagation(); setOpen(false) }
        else if (event.key === 'Tab') setOpen(false)
        else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          const now = Date.now(); search.current = { text: (now - search.current.at < 700 ? search.current.text : '') + event.key.toLowerCase(), at: now }
          const found = options.findIndex(option => !option.disabled && String(option.label).toLowerCase().startsWith(search.current.text))
          if (found >= 0) { event.preventDefault(); if (open) setActive(found); else choose(options[found]) }
        }
      }}>
      <span className={selected ? '' : 'select-placeholder'}>{options[index]?.label ?? '선택'}</span><svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="m4 6 4 4 4-4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/></svg>
    </button>
    <div ref={layer} id={`${id}-list`} role="listbox" aria-label={label} popover="auto" hidden={!open} className="select-menu" style={position} onToggle={event => { if ((event.nativeEvent as ToggleEvent).newState === 'closed') setOpen(false) }}>
      {options.map((option, i) => <div key={option.value} id={`${id}-${i}`} role="option" aria-selected={selected === option.value} aria-disabled={option.disabled || undefined} className={`select-option ${active === i ? 'is-active' : ''}`} onPointerMove={() => setActive(i)} onPointerDown={event => event.preventDefault()} onClick={() => choose(option)}>
        <span>{option.label}</span>{selected === option.value && <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="m3 8 3 3 7-7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>}
      </div>)}
    </div>
  </div>
}
