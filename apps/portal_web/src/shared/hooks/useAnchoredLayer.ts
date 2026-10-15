import { useLayoutEffect, useRef, useState, type RefObject } from 'react'

export function useAnchoredLayer(open: boolean, anchor: RefObject<HTMLElement | null>, width?: number) {
  const layer = useRef<HTMLDivElement>(null)
  const [position, setPosition] = useState({ left: 0, top: 0, width: 0, maxHeight: 320 })
  useLayoutEffect(() => {
    const element = layer.current
    if (!element || !open) return
    element.showPopover?.()
    function place() {
      if (!anchor.current || !element) return
      const rect = anchor.current.getBoundingClientRect()
      const available = Math.max(80, window.innerHeight - 24)
      const size = Math.min(width ?? rect.width, window.innerWidth - 24)
      element.style.width = `${size}px`
      const height = Math.min(element.scrollHeight || 280, 320, available)
      const below = window.innerHeight - rect.bottom - 12
      setPosition({
        left: Math.max(12, Math.min(rect.left, window.innerWidth - size - 12)),
        top: below >= height ? rect.bottom + 6 : Math.max(12, rect.top - height - 6),
        width: size,
        maxHeight: Math.min(320, available)
      })
    }
    place()
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
    return () => {
      element.hidePopover?.()
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
    }
  }, [open, anchor, width])
  return { layer, position }
}
