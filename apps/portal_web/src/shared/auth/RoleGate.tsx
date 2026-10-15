import type { ReactNode } from 'react'
import { useAuth } from './AuthContext'
import { usePortalConnection } from '../hooks/usePortalConnection'
import { WorkspaceShell } from '../components/WorkspaceShell'
import { Panel } from '../components/Panel'
import { LoginForm } from '../components/LoginForm'
import hospitalSymbol from '../../hospital/assets/favilium-symbol.svg'

export function RoleGate({ role, children }: { role: 'guardian' | 'hospital'; children: ReactNode }) {
  const auth = useAuth()
  const connection = usePortalConnection()
  const hospital = role === 'hospital'
  const allowed = Boolean(auth.token && auth.access?.[role])
  if (allowed) return children
  return <WorkspaceShell area={hospital ? '병원' : '보호자'} brandSymbol={hospital ? hospitalSymbol : undefined}
    title={hospital ? '병원 업무' : '가족의 공간'} subtitle={hospital ? '환자와 전달 관리' : '목소리와 기억을 함께'}
    current="로그인" navigation={null}>
    <div className="auth-layout"><Panel title={auth.token ? '접근 권한을 확인해주세요' : hospital ? '병원 직원 로그인' : '보호자 로그인'}
      description={auth.token ? '현재 계정에는 이 공간의 접근 권한이 없습니다.' : '계정으로 로그인해 나의 공간을 시작하세요.'}>
      {auth.token ? <><a href={auth.access?.hospital ? '/hospital' : '/studio'}>내 공간으로 이동</a><button onClick={auth.signOut}>로그아웃</button></> :
      <LoginForm kind={hospital ? '병원 직원' : '보호자'} ready={connection.ready} onLogin={auth.signIn} />}
      {connection.error && <div role="alert"><p>로그인 서비스에 연결하지 못했습니다.</p><button onClick={() => void connection.retry()}>다시 연결</button></div>}
      {auth.logoutError && <p role="alert">{auth.logoutError}</p>}
    </Panel></div>
  </WorkspaceShell>
}
