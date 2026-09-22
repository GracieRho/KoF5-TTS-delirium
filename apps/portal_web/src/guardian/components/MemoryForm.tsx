import { useEffect, useState, type FormEvent } from 'react'
import type { FamilyFact } from '../../shared/types/domain'
import { FAMILY_LABELS } from '../../shared/types/constants'

const prompts: [string, string][] = [['relationship','환자분과 어떤 관계인가요?'],['family','가족과 함께한 이야기가 있나요?'],['hometown','고향은 어디였나요?'],['occupation','예전에 어떤 일을 하셨나요?'],['food','좋아하는 음식은 무엇인가요?'],['hobby','좋아하는 음악이나 취미는 무엇인가요?'],['daily_routine','평소 하루 일과는 어땠나요?'],['comfort_topic','환자분을 안심시키는 이야기는 무엇인가요?'],['avoid_topic','대화에서 피해야 할 이야기가 있나요?']]

export function MemoryForm({ editing, busy, onSave, onCancel }: { editing: FamilyFact | null; busy: boolean; onSave: (category: string, content: string, id?: string) => Promise<void>; onCancel: () => void }) {
  const [category, setCategory] = useState('family'); const [content, setContent] = useState('')
  useEffect(() => { setCategory(editing?.category ?? 'family'); setContent(editing?.content ?? '') }, [editing])
  async function submit(event: FormEvent) { event.preventDefault(); await onSave(category, content.trim(), editing?.fact_id); if (!editing) setContent('') }
  return <form className="form-stack" onSubmit={submit}>
    <label>시작 질문<select defaultValue="" onChange={e => { const value = Number(e.target.value); if (e.target.value && !Number.isNaN(value)) setCategory(prompts[value][0]) }}><option value="">질문을 골라보세요</option>{prompts.map(([, question], index) => <option key={question} value={index}>{question}</option>)}</select></label>
    <label>기억 종류<select value={category} onChange={e => setCategory(e.target.value)}>{Object.entries(FAMILY_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
    <label>확인한 이야기<textarea maxLength={1000} required value={content} onChange={e => setContent(e.target.value)} placeholder="예: 함께 제주도에 갔을 때 성산일출봉을 좋아하셨어요." /></label>
    <div className="button-row"><button className="primary" disabled={busy || !content.trim()}>{editing ? '수정 저장' : '기억 저장'}</button>{editing && <button type="button" onClick={onCancel}>수정 취소</button>}</div>
  </form>
}
