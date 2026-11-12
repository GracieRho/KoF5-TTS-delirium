import { lazy, StrictMode, Suspense } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import './shared/styles/tokens.css'
import './voice/workspace.css'

const research = /^\/research\/?$/.test(window.location.pathname)
const Research = lazy(() => import('./research/Research'))
if (research) document.title = 'Favilium · 연구 음성 보관함'
createRoot(document.getElementById('root')!).render(<StrictMode>{research
  ? <Suspense fallback={<p role="status">연구 음성 보관함을 여는 중입니다.</p>}><Research /></Suspense>
  : <App />}</StrictMode>)
