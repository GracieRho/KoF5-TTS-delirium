import symbol from '../assets/brand/favilium-symbol.svg'
import wordmark from '../assets/brand/favilium-wordmark.svg'

export function AppHeader() {
  return (
    <header className="app-header guardian-header">
      <div className="brand-block">
        <a className="brand" aria-label="Favilium" href="/studio">
          <img className="brand-symbol" src={symbol} alt="" width="40" height="30" />
          <img className="brand-wordmark" src={wordmark} alt="" width="132" height="30" />
        </a>
      </div>
    </header>
  )
}
