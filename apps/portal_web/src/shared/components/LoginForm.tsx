import { useState, type FormEvent } from 'react'
import { StatusMessage } from './StatusMessage'

export function LoginForm({ kind, ready, onLogin, onSignup }: { kind: '보호자' | '병원 직원'; ready: boolean; onLogin: (email: string, password: string) => Promise<void>; onSignup?: (email: string, password: string) => Promise<void> }) {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false); const [status, setStatus] = useState('')
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); setStatus('로그인과 권한을 확인하고 있습니다.'); try { await onLogin(email, password); setPassword('') } catch { setStatus('로그인 또는 권한 확인에 실패했습니다.') } finally { setBusy(false) } }
  async function signup() { if (!onSignup || !email || !password) return; setBusy(true); try { await onSignup(email, password); setStatus('계정을 만들었습니다. 확인 이메일이 있다면 인증 후 로그인하세요.') } catch { setStatus('계정을 만들지 못했습니다. 이메일과 비밀번호를 확인하세요.') } finally { setBusy(false) } }
  return <form onSubmit={submit} className="form-stack">
    <label>이메일<input aria-label="이메일" type="email" autoComplete="username" required value={email} onChange={e => setEmail(e.target.value)} /></label>
    <label>비밀번호<input aria-label="비밀번호" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} /></label>
    <button className="primary" disabled={!ready || busy}>{busy ? '확인 중' : `${kind} 로그인`}</button>
    {onSignup && <button className="secondary" type="button" disabled={!ready || busy || !email || !password} onClick={signup}>보호자 계정 만들기</button>}
    <StatusMessage>{status || (ready ? '로그인할 수 있습니다.' : '전용 로그인 연결을 확인하고 있습니다.')}</StatusMessage>
  </form>
}
