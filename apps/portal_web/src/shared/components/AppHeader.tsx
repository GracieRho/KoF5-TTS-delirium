export function AppHeader({ area }: { area: '보호자' | '병원' }) {
  return <header className={`app-header ${area === '병원' ? 'hospital-header' : 'guardian-header'}`}>
    <div className="brand-block"><a className="brand" href={area === '보호자' ? '/guardian' : '/hospital'}><span aria-hidden="true">F</span> Familiar Voice</a><span className="workspace-label">{area} 공간</span></div>
    <nav aria-label="포털 이동"><span className="nav-label">다른 공간</span><a href={area === '보호자' ? '/hospital' : '/guardian'}>{area === '보호자' ? '병원 업무' : '보호자 기억'}</a></nav>
  </header>
}
