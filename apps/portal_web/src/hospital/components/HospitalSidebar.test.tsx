import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { HospitalSidebar } from './HospitalSidebar'

it('전역 병원 업무와 환자 선택을 분리한다', () => {
  const onView = vi.fn(); const onRegister = vi.fn()
  render(<HospitalSidebar view="patients" patients={[]} queueCount={2} onView={onView} onSelect={vi.fn()} onRegister={onRegister} onSignOut={vi.fn()}/>)
  fireEvent.click(screen.getByRole('button', { name: /전체 전달 대기/ })); expect(onView).toHaveBeenCalledWith('queue')
  fireEvent.click(screen.getByRole('button', { name: '환자 등록' })); expect(onRegister).toHaveBeenCalledOnce()
})
