import { afterEach, describe, expect, it, vi } from 'vitest'
import { SupabaseRest } from './supabase'

describe('Supabase 인증 오류', () => {
  afterEach(() => vi.unstubAllGlobals())
  it('오류가 난 요청의 토큰을 중앙 핸들러에 전달한다', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 401 })))
    const onAuthError = vi.fn(); const api = new SupabaseRest({ url: 'https://example.test', publishable_key: 'pk' }, onAuthError)
    await expect(api.request('/rest/v1/test', { token: 'old-token' })).rejects.toMatchObject({ status: 401 })
    expect(onAuthError).toHaveBeenCalledWith('old-token')
  })
})
