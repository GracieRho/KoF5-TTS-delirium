import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { AuthProvider } from './shared/auth/AuthContext'
import { ToastProvider } from './shared/components/StatusMessage'
import './shared/styles/tokens.css'

createRoot(document.getElementById('root')!).render(<StrictMode><ToastProvider><AuthProvider><App/></AuthProvider></ToastProvider></StrictMode>)
