import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { loadConfig } from '../api/http'
import { SupabaseRest } from '../api/supabase'
import type { PortalConfig } from '../types/domain'

type AuthState = {
  config: PortalConfig | null; api: SupabaseRest | null; token: string | null; userId: string | null;
  connect: (path?: string) => Promise<void>; signIn: (email: string, password: string) => Promise<void>; signUp: (email: string, password: string) => Promise<void>; signOut: () => void;
}
const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [config, setConfig] = useState<PortalConfig | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const api = useMemo(() => config ? new SupabaseRest(config) : null, [config])
  const connect = useCallback(async (path = '/portal/config') => { setConfig(await loadConfig(path)) }, [])
  async function signIn(email: string, password: string) {
    if (!api) throw new Error('unconfigured')
    const session = await api.signIn(email.trim(), password)
    setToken(session.access_token); setUserId(session.user?.id ?? null)
  }
  async function signUp(email: string, password: string) { if (!api) throw new Error('unconfigured'); await api.signUp(email.trim(), password) }
  function signOut() { setToken(null); setUserId(null) }
  return <AuthContext.Provider value={{ config, api, token, userId, connect, signIn, signUp, signOut }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('AuthProvider is required')
  return value
}
