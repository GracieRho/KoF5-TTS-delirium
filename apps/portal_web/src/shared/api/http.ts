import type { PortalConfig } from '../types/domain'

export class ApiError extends Error {
  constructor(public status: number, message = String(status)) { super(message) }
}

export async function readJson<T>(response: Response): Promise<T> {
  if (!response.ok) throw new ApiError(response.status)
  const text = await response.text()
  return (text ? JSON.parse(text) : null) as T
}

export async function loadConfig(path = '/portal/config'): Promise<PortalConfig> {
  return readJson<PortalConfig>(await fetch(path, { headers: { Accept: 'application/json' } }))
}
