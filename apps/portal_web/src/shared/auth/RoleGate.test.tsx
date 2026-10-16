import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { RoleGate } from './RoleGate'
const state = vi.hoisted(() => ({ token: null as string | null, access: null as null | {guardian:boolean;hospital:boolean}, error:false, retry:vi.fn() }))
vi.mock('./AuthContext', () => ({ useAuth: () => ({...state, signOut:vi.fn(), signIn:vi.fn()}) }))
vi.mock('../hooks/usePortalConnection', () => ({usePortalConnection: () => ({ready:true,error:state.error,retry:state.retry})}))
beforeEach(() => { state.token=null; state.access=null; state.error=false; state.retry.mockClear() })
it('로그인 전에는 보호자 자료를 마운트하지 않는다', () => {
  render(<RoleGate role="guardian"><h1>private workspace</h1></RoleGate>)
  expect(screen.queryByText('private workspace')).not.toBeInTheDocument()
})
it('병원 세션으로 보호자 공간을 직접 열어도 자료가 노출되지 않는다', () => {
  state.token='staff'; state.access={guardian:false,hospital:true}
  render(<RoleGate role="guardian"><h1>private workspace</h1></RoleGate>)
  expect(screen.queryByText('private workspace')).not.toBeInTheDocument()
  expect(screen.getByRole('link',{name:'내 공간으로 이동'})).toHaveAttribute('href','/hospital')
})
it('설정 연결 실패를 숨기지 않고 재시도할 수 있다', () => {
  state.error=true
  render(<RoleGate role="hospital">private workspace</RoleGate>)
  expect(screen.getByRole('alert')).toHaveTextContent('로그인 서비스에 연결하지 못했습니다.')
  fireEvent.click(screen.getByRole('button',{name:'다시 연결'})); expect(state.retry).toHaveBeenCalledOnce()
})
