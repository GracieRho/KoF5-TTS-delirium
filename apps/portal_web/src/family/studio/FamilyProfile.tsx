import { useState, type FormEvent } from 'react'
import { SPEECH_STYLE_LABELS, type Profile } from './api'
import { Select } from '../../shared/components/Select'

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
  const [aliases, setAliases] = useState((profile.address_aliases ?? []).join(', '))
  function field(key: 'guardian_name' | 'patient_alias' | 'relationship' | 'address_as', label: string, placeholder: string) {
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
    await onSave({ ...draft, address_aliases: [...new Set(aliases.split(',').map(value => value.trim()).filter(Boolean))] })
  }
  return (
    <form className="form-stack" onSubmit={submit}>
      {field('guardian_name', '나의 이름', '예: 수민')}
      {field('patient_alias', '대화 상대의 별칭', '예: 아버지')}
      {field('relationship', '우리의 관계', '예: 딸')}
      {field('address_as', '주로 부르는 호칭', '예: 아빠')}
      <label className="field">다른 호칭들 (쉼표로 구분)
        <input maxLength={245} value={aliases} placeholder="예: 아버지, 우리 아빠" onChange={event => setAliases(event.target.value)} />
      </label>
      <Select label="평소 말투" required value={draft.speech_style ?? ''}
        onValueChange={value => setDraft({ ...draft, speech_style: value as Profile['speech_style'] })}>
        <option value="" disabled>말투를 골라주세요</option>
        {Object.entries(SPEECH_STYLE_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </Select>
      <button className="primary" disabled={busy}>
        가족 소개 저장
      </button>
    </form>
  )
}
