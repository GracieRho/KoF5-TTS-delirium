import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react'
import { loadConfig } from '../api/http'
import { SupabaseRest } from '../api/supabase'
import type { PortalConfig } from '../types/domain'
import { shouldClearSession } from './sessionGuard'

type AuthState = {
  config: PortalConfig | null; api: SupabaseRest | null; token: string | null; userId: string | null;
  connect: (path?: string) => Promise<void>; signIn: (email: string, password: string) => Promise<void>; signUp: (email: string, password: string) => Promise<void>; signOut: () => void;
  handleAuthError: (requestToken: string) => void;
}
const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [config, setConfig] = useState<PortalConfig | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const tokenRef = useRef<string | null>(null); const loginGeneration = useRef(0)
  const setSession = useCallback((nextToken: string | null, nextUserId: string | null) => { tokenRef.current = nextToken; setToken(nextToken); setUserId(nextUserId) }, [])
  const handleAuthError = useCallback((requestToken: string) => { if (shouldClearSession(tokenRef.current, requestToken)) { loginGeneration.current += 1; setSession(null, null) } }, [setSession])
  const api = useMemo(() => config ? new SupabaseRest(config, handleAuthError) : null, [config, handleAuthError])
  const connect = useCallback(async (path = '/portal/config') => { setConfig(await loadConfig(path)) }, [])
  async function signIn(email: string, password: string) {
    if (!api) throw new Error('unconfigured')
    const generation = ++loginGeneration.current
    const session = await api.signIn(email.trim(), password)
    if (generation !== loginGeneration.current) return
    setSession(session.access_token, session.user?.id ?? null)
  }
  async function signUp(email: string, password: string) { if (!api) throw new Error('unconfigured'); await api.signUp(email.trim(), password) }
  const signOut = useCallback(() => { loginGeneration.current += 1; setSession(null, null) }, [setSession])
  return <AuthContext.Provider value={{ config, api, token, userId, connect, signIn, signUp, signOut, handleAuthError }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('AuthProvider is required')
  return value
}
