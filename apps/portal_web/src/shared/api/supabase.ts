import { ApiError, readJson } from './http'
import type { PortalConfig, Session } from '../types/domain'

type Options = { method?: string; body?: unknown; token?: string | null; schema?: 'api'; returnRow?: boolean }

export class SupabaseRest {
  constructor(private config: PortalConfig) {}

  async request<T>(path: string, options: Options = {}): Promise<T> {
    const method = options.method ?? 'GET'
    const headers: Record<string, string> = { apikey: this.config.publishable_key, Accept: 'application/json' }
    if (options.token) headers.Authorization = `Bearer ${options.token}`
    if (options.schema) headers[method === 'GET' ? 'Accept-Profile' : 'Content-Profile'] = options.schema
    if (options.body !== undefined) headers['Content-Type'] = 'application/json'
    if (options.returnRow) headers.Prefer = 'return=representation'
    const response = await fetch(this.config.url + path, { method, headers, body: options.body === undefined ? undefined : JSON.stringify(options.body) })
    return readJson<T>(response)
  }

  signIn(email: string, password: string) {
    return this.request<Session>('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } })
  }

  signUp(email: string, password: string) {
    return this.request<unknown>('/auth/v1/signup', { method: 'POST', body: { email, password } })
  }

  async safe<T>(path: string, options: Options = {}) {
    try { return await this.request<T>(path, options) }
    catch (error) { if (error instanceof ApiError) throw error; throw new ApiError(0, 'network') }
  }
}
