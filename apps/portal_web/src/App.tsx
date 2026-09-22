import { GuardianPortal } from './guardian/pages/GuardianPortal'
import { HospitalPortal } from './hospital/pages/HospitalPortal'

export function App() {
  const path = window.location.pathname.replace(/\/$/, '')
  if (path === '/hospital') return <HospitalPortal/>
  if (path === '/guardian' || path === '') return <GuardianPortal/>
  return <main className="page"><h1>화면을 찾을 수 없습니다.</h1><p><a href="/guardian">보호자 화면</a> 또는 <a href="/hospital">병원 화면</a>으로 이동하세요.</p></main>
}
