import { useState, type FormEvent } from 'react'
import type { Profile } from './api'

export function FamilyProfile({
  profile,
  busy,
  onSave
}: {
  profile: Profile
  busy: boolean
  onSave: (profile: Profile) => Promise<void>
}) {
  const [draft, setDraft] = useState(profile)
  function field(key: keyof Profile, label: string, placeholder: string) {
    return (
      <label className="field">
        {label}
        <input
          required
          maxLength={40}
          value={draft[key]}
          placeholder={placeholder}
          onChange={(event) => setDraft({ ...draft, [key]: event.target.value })}
        />
      </label>
    )
  }
  async function submit(event: FormEvent) {
    event.preventDefault()
    await onSave(draft)
  }
  return (
    <form className="form-stack" onSubmit={submit}>
      {field('guardian_name', '나의 이름', '예: 수민')}
      {field('patient_alias', '대화 상대의 별칭', '예: 아버지')}
      {field('relationship', '우리의 관계', '예: 딸')}
      {field('address_as', '평소 부르는 호칭', '예: 아빠')}
      <button className="primary" disabled={busy}>
        가족 소개 저장
      </button>
    </form>
  )
}
