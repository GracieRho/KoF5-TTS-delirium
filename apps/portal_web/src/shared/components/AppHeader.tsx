import symbol from '../assets/brand/favilium-symbol.svg'
import wordmark from '../assets/brand/favilium-wordmark.svg'

export function AppHeader({
  area,
  homeHref,
  brandSymbol = symbol
}: {
  area: '보호자' | '병원'
  homeHref?: string
  brandSymbol?: string
}) {
  return (
    <header className={`app-header ${area === '병원' ? 'hospital-header' : 'guardian-header'}`}>
      <div className="brand-block">
        <a
          className="brand"
          aria-label="Favilium"
          href={homeHref ?? (area === '보호자' ? '/studio' : '/hospital')}
        >
          <img className="brand-symbol" src={brandSymbol} alt="" width="40" height="30" />
          <img className="brand-wordmark" src={wordmark} alt="" width="132" height="30" />
        </a>
        <span className="workspace-label">{area} 공간</span>
      </div>

    </header>
  )
}
