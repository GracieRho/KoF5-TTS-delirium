import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthContext'

export function usePortalConnection(path = '/portal/config') {
  const { config, connect } = useAuth()
  const [error, setError] = useState(false)
  const retry = useCallback(async () => {
    setError(false)
    try { await connect(path) } catch { setError(true) }
  }, [connect, path])
  useEffect(() => { if (!config) void retry() }, [config, retry])
  return { ready: Boolean(config), error, retry }
}
