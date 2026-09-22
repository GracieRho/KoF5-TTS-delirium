import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { LoginForm } from './LoginForm'

describe('역할 로그인', () => {
  it('연결 전 로그인을 막고 자격값을 노출하지 않는다', () => {
    render(<LoginForm kind="병원 직원" ready={false} onLogin={vi.fn()}/>)
    expect(screen.getByRole('button', { name: '병원 직원 로그인' })).toBeDisabled(); expect(screen.queryByText(/publishable|apikey|token/i)).not.toBeInTheDocument()
  })
  it('입력한 계정으로 로그인한다', async () => {
    const login = vi.fn().mockResolvedValue(undefined); render(<LoginForm kind="보호자" ready onLogin={login}/>)
    fireEvent.change(screen.getByLabelText('이메일'), { target: { value: 'g@example.com' } }); fireEvent.change(screen.getByLabelText('비밀번호'), { target: { value: 'secret' } }); fireEvent.click(screen.getByRole('button', { name: '보호자 로그인' }))
    await waitFor(() => expect(login).toHaveBeenCalledWith('g@example.com', 'secret'))
  })
})
