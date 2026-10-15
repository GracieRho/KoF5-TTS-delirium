import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react'
import { loadConfig } from '../api/http'
import { SupabaseRest } from '../api/supabase'
import type { PortalConfig } from '../types/domain'
import { shouldClearSession } from './sessionGuard'

export type PortalAccess = { user_id: string; guardian: boolean; hospital: boolean }
type AuthState = {
  access: PortalAccess | null; logoutError: string;
  config: PortalConfig | null; api: SupabaseRest | null; token: string | null; userId: string | null;
  connect: (path?: string) => Promise<void>; signIn: (email: string, password: string) => Promise<void>; signUp: (email: string, password: string) => Promise<void>; signOut: () => void;
  handleAuthError: (requestToken: string) => void;
}
const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [logoutError, setLogoutError] = useState('')
  const [access, setAccess] = useState<PortalAccess | null>(null)
  const [config, setConfig] = useState<PortalConfig | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const tokenRef = useRef<string | null>(null); const loginGeneration = useRef(0)
  const setSession = useCallback((nextToken: string | null, nextUserId: string | null) => { tokenRef.current = nextToken; setToken(nextToken); setUserId(nextUserId) }, [])
  const handleAuthError = useCallback((requestToken: string) => { if (shouldClearSession(tokenRef.current, requestToken)) { loginGeneration.current += 1; setAccess(null); sessionStorage.removeItem('favilium.session'); setSession(null, null) } }, [setSession])
  const api = useMemo(() => config ? new SupabaseRest(config, handleAuthError) : null, [config, handleAuthError])
  const connect = useCallback(async (path = '/portal/config') => {
    const next = await loadConfig(path)
    const generation = loginGeneration.current
    const saved = sessionStorage.getItem('favilium.session')
    if (saved) {
      try {
        const verified = await new SupabaseRest(next).request<PortalAccess | null>('/rest/v1/rpc/portal_access', { method: 'POST', token: saved, schema: 'api', body: {} })
        if (generation === loginGeneration.current && verified && (verified.guardian || verified.hospital)) { setSession(saved, verified.user_id); setAccess(verified) }
        else if (generation === loginGeneration.current) sessionStorage.removeItem('favilium.session')
      } catch { if (generation === loginGeneration.current) sessionStorage.removeItem('favilium.session') }
    }
    setConfig(next)
  }, [setSession])
  async function signIn(email: string, password: string) {
    if (!api) throw new Error('unconfigured')
    setLogoutError('')
    const generation = ++loginGeneration.current
    const session = await api.signIn(email.trim(), password)
    const verified = await api.request<PortalAccess | null>('/rest/v1/rpc/portal_access', { method: 'POST', token: session.access_token, schema: 'api', body: {} })
    if (generation !== loginGeneration.current) return
    if (!verified || (!verified.guardian && !verified.hospital)) throw new Error('승인된 접근 권한이 없습니다.')
    sessionStorage.setItem('favilium.session', session.access_token)
    setSession(session.access_token, verified.user_id)
    setAccess(verified)
  }
  async function signUp(email: string, password: string) { if (!api) throw new Error('unconfigured'); await api.signUp(email.trim(), password) }
  const signOut = useCallback(() => {
    const previous = tokenRef.current
    loginGeneration.current += 1
    setAccess(null); sessionStorage.removeItem('favilium.session'); setSession(null, null)
    if (previous && api) void api.request('/auth/v1/logout?scope=local', { method: 'POST', token: previous }).catch(() => {
      setLogoutError('이 화면에서는 로그아웃했습니다. 서버 연결을 확인하지 못해 세션 종료 확인이 필요합니다.')
    })
  }, [api, setSession])

  return <AuthContext.Provider value={{ access, logoutError, config, api, token, userId, connect, signIn, signUp, signOut, handleAuthError }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('AuthProvider is required')
  return value
}
