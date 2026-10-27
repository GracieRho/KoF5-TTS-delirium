import type { Profile, StudioState } from './api'

export function profileReady(profile: Profile) {
  return [profile.guardian_name, profile.patient_alias, profile.relationship, profile.address_as].every(value => Boolean(value.trim()))
}

export function conversationReadiness(state: StudioState) {
  const steps = [
    profileReady(state.profile),
    state.voice.status === 'created',
    state.memories.some((memory) => memory.category !== 'avoid')
  ]
  const missing: { label: string; target?: 'profile' | 'voice' | 'memory' }[] = []
  if (!steps[0]) missing.push({ label: '가족 소개 입력', target: 'profile' })
  if (!steps[1]) missing.push({ label: '목소리 등록 확인', target: 'voice' })
  if (!steps[2]) missing.push({ label: '가족 기억 추가', target: 'memory' })
  if (!state.providers.voice) missing.push({ label: '음성 서비스 연결 필요' })
  if (!state.providers.conversation) missing.push({ label: '대화 서비스 연결 필요' })
  return { steps, missing, ready: missing.length === 0 }
}
