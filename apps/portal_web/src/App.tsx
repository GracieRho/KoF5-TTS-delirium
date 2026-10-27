import { Research } from './family/research/Research'
import { Studio } from './family/studio/Studio'
import { HospitalPortal } from './hospital/pages/HospitalPortal'
import { RoleGate } from './shared/auth/RoleGate'

export function App() {
  const path = window.location.pathname.replace(/\/$/, '')
  if (path === '/guardian' || path === '') {
    window.location.replace(path === '/guardian' ? '/studio?tab=linked' : '/studio')
    return null
  }
  if (path === '/research') return <Research />
  if (path === '/studio') return <RoleGate role="guardian"><Studio /></RoleGate>
  if (path === '/hospital') return <RoleGate role="hospital"><HospitalPortal /></RoleGate>
  return <main className="page"><h1>화면을 찾을 수 없습니다.</h1><a href="/studio">시작 화면으로</a></main>
}
