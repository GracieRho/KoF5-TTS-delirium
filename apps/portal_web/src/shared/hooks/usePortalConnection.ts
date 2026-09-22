import { useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthContext'

export function usePortalConnection(path = '/portal/config') {
  const { config, connect } = useAuth()
  const [error, setError] = useState(false)
  useEffect(() => { if (!config) void connect(path).catch(() => setError(true)) }, [config, connect, path])
  return { ready: Boolean(config), error }
}
