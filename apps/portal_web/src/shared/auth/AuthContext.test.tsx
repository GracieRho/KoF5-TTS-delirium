import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { AuthProvider, useAuth } from './AuthContext'

const mocks = vi.hoisted(() => ({ request: vi.fn(), signIn: vi.fn(), config: vi.fn() }))
vi.mock('../api/http', () => ({ loadConfig: mocks.config }))
vi.mock('../api/supabase', () => ({ SupabaseRest: class {
  request = mocks.request
  signIn = mocks.signIn
} }))
function Probe() {
  const auth = useAuth()
  return <><output>{auth.config ? 'ready' : 'waiting'}|{auth.access?.guardian ? 'guardian' : auth.access?.hospital ? 'hospital' : 'signed-out'}</output>
    <button onClick={() => void auth.connect()}>connect</button>
    <button onClick={() => void auth.signIn('guardian@email.com','test1234').catch(() => undefined)}>login</button>
    <button onClick={auth.signOut}>logout</button></>
}
beforeEach(() => {
  sessionStorage.clear(); vi.clearAllMocks()
  mocks.config.mockResolvedValue({url:'http://127.0.0.1:54341',publishable_key:'sb_publishable_test'})
  mocks.signIn.mockResolvedValue({access_token:'signed-token',user:{id:'user',user_metadata:{hospital:true}}})
  mocks.request.mockResolvedValue({user_id:'user',guardian:true,hospital:false})
})
async function connect() {
  render(<AuthProvider><Probe /></AuthProvider>)
  fireEvent.click(screen.getByText('connect'))
  await screen.findByText(/ready/)
}
it('프로필 주장 대신 서버 권한으로 로그인하고 서버의 현재 세션을 종료한다', async () => {
  await connect(); fireEvent.click(screen.getByText('login'))
  await screen.findByText('ready|guardian')
  expect(sessionStorage.getItem('favilium.session')).toBe('signed-token')
  fireEvent.click(screen.getByText('logout'))
  expect(screen.getByText('ready|signed-out')).toBeInTheDocument()
  expect(sessionStorage.getItem('favilium.session')).toBeNull()
  expect(mocks.request).toHaveBeenLastCalledWith('/auth/v1/logout?scope=local',expect.objectContaining({token:'signed-token'}))
})
it('복원 시 폐기된 세션은 저장소와 화면에서 제거한다', async () => {
  sessionStorage.setItem('favilium.session','revoked-token')
  mocks.request.mockResolvedValue(null)
  await connect()
  expect(screen.getByText('ready|signed-out')).toBeInTheDocument()
  expect(sessionStorage.getItem('favilium.session')).toBeNull()
})
it('로그아웃 중 도착한 로그인 응답이 세션을 복원하지 않는다', async () => {
  await connect()
  let resolve!: (value: unknown) => void
  mocks.signIn.mockReturnValue(new Promise(r => { resolve = r }))
  fireEvent.click(screen.getByText('login')); fireEvent.click(screen.getByText('logout'))
  resolve({access_token:'late-token'})
  await waitFor(() => expect(mocks.request).toHaveBeenCalled())
  expect(screen.getByText('ready|signed-out')).toBeInTheDocument()
  expect(sessionStorage.getItem('favilium.session')).toBeNull()
})
