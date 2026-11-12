import symbol from '../assets/brand/favilium-symbol.svg'
import researchSymbol from '../../research/assets/favilium-symbol.svg'
import wordmark from '../assets/brand/favilium-wordmark.svg'

export function AppHeader({ research = false }: { research?: boolean }) {
  return (
    <header className="app-header guardian-header">
      <div className="brand-block">
        <a className="brand" aria-label="Favilium" href={research ? window.location.pathname + window.location.hash : '/studio'}>
          <img className="brand-symbol" src={research ? researchSymbol : symbol} alt="" width="40" height="30" />
          <img className="brand-wordmark" src={wordmark} alt="" width="132" height="30" />
        </a>
      </div>
    </header>
  )
}
