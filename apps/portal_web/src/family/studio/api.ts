export type Profile = {
  guardian_name: string
  patient_alias: string
  relationship: string
  address_as: string
  address_aliases?: string[]
  speech_style?: 'polite' | 'casual' | 'mixed'
}
export const SPEECH_STYLE_LABELS = { polite: '존댓말', casual: '반말', mixed: '반존대' } as const
export type MemoryInput = {
  title: string
  category: 'family' | 'story' | 'comfort' | 'avoid'
  content: string
}
export type Memory = MemoryInput & { id: string; created_at: string }
export type StudioState = {
  profile: Profile
  memories: Memory[]
  voice: {
    status:
      | 'none'
      | 'failed'
      | 'pending'
      | 'verification_pending'
      | 'created'
      | 'deletion_pending'
      | 'deleted'
  }
  providers: { voice: boolean; conversation: boolean; transcription: boolean }
}
export type TurnResult = { reply: string; audio_base64: string; memory_count: number }
export async function studioRequest<T>(path: string, method = 'GET', data?: unknown): Promise<T> {
  const response = await fetch(`/local-studio${path}`, {
    method,
    headers: {
      'X-Kof5-Studio': '1',
      Authorization: `Bearer ${sessionStorage.getItem('favilium.session') ?? ''}`,
      ...(data === undefined ? {} : { 'Content-Type': 'application/json' })
    },
    body: data === undefined ? undefined : JSON.stringify(data),
    cache: 'no-store'
  })
  if (!response.ok) {
    const body = await response.json().catch(() => null)
    throw new Error(
      typeof body?.detail === 'string' ? body.detail : '입력 내용과 서버 연결을 확인해주세요.'
    )
  }
  return response.json() as Promise<T>
}
