import { useRef, type KeyboardEvent } from 'react'
export type HospitalTab = 'summary' | 'queue' | 'registration' | 'messages' | 'context' | 'safety' | 'device'
const labels: [HospitalTab, string][] = [['summary','입원 정보'],['queue','전달 대기'],['registration','환자 등록'],['messages','메시지 승인'],['context','병원 맥락'],['safety','전사·경고'],['device','기기·음성']]
export function HospitalTabs({ value, onChange, synthetic }: { value: HospitalTab; onChange: (value: HospitalTab) => void; synthetic: boolean }) {
  const refs = useRef<Array<HTMLButtonElement | null>>([]); const visible = labels.filter(([id]) => synthetic || !['messages','context','safety','device'].includes(id))
  function move(event: KeyboardEvent, index: number) { const key = event.key; if (!['ArrowLeft','ArrowRight','Home','End'].includes(key)) return; event.preventDefault(); const next = key === 'Home' ? 0 : key === 'End' ? visible.length - 1 : (index + (key === 'ArrowRight' ? 1 : -1) + visible.length) % visible.length; onChange(visible[next][0]); refs.current[next]?.focus() }
  return <div className="tabs" role="tablist" aria-label="병원 업무">{visible.map(([id,label], index) => <button id={`hospital-tab-${id}`} aria-controls={`hospital-panel-${id}`} key={id} ref={element => { refs.current[index] = element }} role="tab" tabIndex={value === id ? 0 : -1} aria-selected={value === id} onKeyDown={event => move(event, index)} onClick={() => onChange(id)}>{label}</button>)}</div>
}
