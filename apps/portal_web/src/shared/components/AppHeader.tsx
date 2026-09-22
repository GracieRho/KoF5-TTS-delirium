export function AppHeader({ area }: { area: '보호자' | '병원' }) {
  return <header className="app-header"><a className="brand" href={area === '보호자' ? '/guardian' : '/hospital'}><span aria-hidden="true">十</span> Familiar Voice</a><nav aria-label="포털 이동"><a href={area === '보호자' ? '/hospital' : '/guardian'}>{area === '보호자' ? '병원 업무 화면' : '보호자 화면'}</a></nav></header>
}
