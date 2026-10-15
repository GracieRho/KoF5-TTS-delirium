import { render, screen } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { GuardianPortal } from './GuardianPortal'
const mocks = vi.hoisted(() => ({ links: vi.fn(), api: {} }))
vi.mock('../../../shared/auth/AuthContext', () => ({useAuth: () => ({api:mocks.api,token:'guardian-token'})}))
vi.mock('../api/guardianApi', async original => ({...await original<typeof import('../api/guardianApi')>(), guardianApi:{links:mocks.links}}))
beforeEach(() => { mocks.links.mockReset() })
it('연결 상태만 표시하고 별도 기억 편집기를 만들지 않는다', async () => {
  mocks.links.mockResolvedValue([{patient_id:'one',relationship:'딸',access_status:'verified',effective_at:'2020-01-01'}])
  render(<GuardianPortal />)
  expect(await screen.findByText('병원 연결 확인됨')).toBeInTheDocument()
  expect(screen.queryByRole('combobox')).not.toBeInTheDocument()
  expect(screen.queryByRole('button',{name:'새 기억'})).not.toBeInTheDocument()
})
it('연결 실패를 빈 성공 목록으로 표시하지 않는다', async () => {
  mocks.links.mockRejectedValue(new Error('offline'))
  render(<GuardianPortal />)
  expect(await screen.findByRole('alert')).toHaveTextContent('가족 연결을 확인하지 못했습니다.')
})
