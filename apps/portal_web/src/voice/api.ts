export type VoiceStatus = {
  authenticated: boolean
  configured: boolean
  voice_state: 'empty' | 'creating' | 'ready' | 'verification' | 'deleting'
  reference?: string | null
}

export async function request(path: string, options: RequestInit = {}): Promise<Response> {
  let response: Response
  try {
    response = await fetch('/api/' + path, { ...options, credentials: 'same-origin', cache: 'no-store' })
  } catch {
    throw new Error('서버에 연결할 수 없습니다. 인터넷 연결을 확인하고 상태를 다시 확인해 주세요.')
  }
  if (!response.ok) {
    const data = await response.json().catch(() => null)
    throw new Error(typeof data?.detail === 'string' ? data.detail : '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.')
  }
  return response
}

export async function readStatus(): Promise<VoiceStatus> {
  return (await request('status')).json()
}

export function jsonPost(data: unknown): RequestInit {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }
}
