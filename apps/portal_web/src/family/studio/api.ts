export type Profile = {
  guardian_name: string
  patient_alias: string
  relationship: string
  address_as: string
}
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
