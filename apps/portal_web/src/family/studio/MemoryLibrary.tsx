import { useState, type FormEvent } from 'react'
import { ResponsiveSheet } from '../../shared/components/ResponsiveSheet'
import { Icon } from '../../shared/components/Icon'
import type { Memory, MemoryInput } from './api'

export const categories = {
  family: '가족과 일상',
  story: '함께한 추억',
  comfort: '좋아하는 것',
  avoid: '피해야 할 이야기'
} as const
export function MemoryLibrary({
  memories,
  busy,
  save,
  remove
}: {
  memories: Memory[]
  busy: boolean
  save: (input: MemoryInput, id?: string) => Promise<boolean>
  remove: (id: string) => Promise<boolean>
}) {
  const [filter, setFilter] = useState('all')
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<Memory | null>(null)
  const [draft, setDraft] = useState<MemoryInput>({ title: '', category: 'story', content: '' })
  function edit(memory: Memory | null) {
    setEditing(memory)
    setDraft(memory ?? { title: '', category: 'story', content: '' })
    setOpen(true)
  }
  async function submit(event: FormEvent) {
    event.preventDefault()
    if (await save(draft, editing?.id)) setOpen(false)
  }
  const visible = memories.filter((memory) => filter === 'all' || memory.category === filter)
  return (
    <section>
      <div className="section-heading">
        <div>
          <h1>가족의 기억</h1>
          <p className="compact">함께한 순간이 대화의 바탕이 됩니다.</p>
        </div>
        <button className="primary" onClick={() => edit(null)}>
          <Icon name="plus" size={17} /> 기억 추가
        </button>
      </div>
      <div className="memory-filters" aria-label="기억 분류">
        {[['all', '전체'], ...Object.entries(categories)].map(([value, label]) => (
          <button key={value} aria-pressed={filter === value} onClick={() => setFilter(value)}>
            {label}
            <span>{memories.filter((m) => value === 'all' || m.category === value).length}</span>
          </button>
        ))}
      </div>
      {visible.length ? (
        <div className="memory-grid">
          {visible.map((memory) => (
            <button
              className={`memory-card ${memory.category === 'avoid' ? 'memory-avoid' : ''}`}
              key={memory.id}
              onClick={() => edit(memory)}
            >
              <span className="memory-category">
                <Icon name={memory.category === 'avoid' ? 'shield' : 'memory'} size={16} />
                {categories[memory.category]}
              </span>
              <h3>{memory.title}</h3>
              <p>{memory.content}</p>
              <span className="memory-date">
                {new Date(memory.created_at).toLocaleDateString('ko-KR')} · 수정하기
              </span>
            </button>
          ))}
        </div>
      ) : (
        <div className="studio-empty">
          <Icon name="memory" size={38} />
          <h2>작은 기억 하나부터 시작해요</h2>
          <p>자주 가던 장소, 좋아하는 음식, 함께 웃었던 순간을 적어주세요.</p>
          <button onClick={() => edit(null)}>첫 기억 추가</button>
        </div>
      )}
      <ResponsiveSheet
        open={open}
        title={editing ? '기억 수정' : '새로운 기억'}
        onClose={() => {
          if (!busy) setOpen(false)
        }}
      >
        <form className="form-stack" onSubmit={submit}>
          <label className="field">
            분류
            <select
              value={draft.category}
              onChange={(e) =>
                setDraft({ ...draft, category: e.target.value as MemoryInput['category'] })
              }
            >
              {Object.entries(categories).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            제목
            <input
              required
              maxLength={80}
              value={draft.title}
              placeholder="예: 함께 다녀온 제주도"
              onChange={(e) => setDraft({ ...draft, title: e.target.value })}
            />
          </label>
          <label className="field">
            기억의 내용
            <textarea
              required
              maxLength={1200}
              rows={7}
              value={draft.content}
              placeholder="누구와, 언제, 무엇을 했는지 구체적으로 적어주세요."
              onChange={(e) => setDraft({ ...draft, content: e.target.value })}
            />
          </label>
          <p className="compact">피해야 할 이야기는 답변의 추억 소재로 사용하지 않습니다.</p>
          <button className="primary" disabled={busy}>
            기억 저장
          </button>
          {editing && (
            <button
              type="button"
              className="danger"
              disabled={busy}
              onClick={async () => {
                if (await remove(editing.id)) setOpen(false)
              }}
            >
              이 기억 삭제
            </button>
          )}
        </form>
      </ResponsiveSheet>
    </section>
  )
}
