import { render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { HospitalSidebar } from './HospitalSidebar'
it('환자 목록에 역할 이동이나 중복 업무 메뉴를 넣지 않는다', () => {
  render(<HospitalSidebar patients={[]} onSelect={vi.fn()} />)
  expect(screen.getByRole('heading', { name: '담당 환자' })).toBeInTheDocument()
  expect(screen.queryByRole('navigation')).not.toBeInTheDocument()
  expect(screen.queryByRole('link')).not.toBeInTheDocument()
})
