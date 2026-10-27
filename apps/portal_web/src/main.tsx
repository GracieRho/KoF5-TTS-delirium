import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { AuthProvider } from './shared/auth/AuthContext'
import { ToastProvider } from './shared/components/StatusMessage'
import './shared/styles/tokens.css'
import { isPersonalizationPage } from './family/components/FamilyNavigation'

const research = isPersonalizationPage()
createRoot(document.getElementById('root')!).render(
  <StrictMode><ToastProvider>{research ? <App /> : <AuthProvider><App /></AuthProvider>}</ToastProvider></StrictMode>
)
