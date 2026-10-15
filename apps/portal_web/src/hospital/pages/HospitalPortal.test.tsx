import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { HospitalPortal } from './HospitalPortal'

const session = vi.hoisted(() => ({ token: null as string | null, select: vi.fn() }))
vi.mock('../../shared/auth/AuthContext', () => ({
  useAuth: () => ({ token: session.token, signIn: vi.fn(), signOut: vi.fn() })
}))
vi.mock('../../shared/hooks/usePortalConnection', () => ({
  usePortalConnection: () => ({ ready: false })
}))
vi.mock('../hooks/useHospitalPortal', () => ({
  useHospitalPortal: () => {
    const patient = {
      patient_id: 'fixture',
      ehr_patient_ref: 'TEST-001',
      staff_display_name: '가상 환자',
      encounter_id: 'test-encounter',
      ward_ref: '시험 병동'
    }
    return {
      api: null,
      token: session.token,
      patients: [patient],
      selected: session.token ? patient : null,
      queue: [],
      facts: [],
      messages: [],
      readiness: [],
      status: '',
      select: session.select
    }
  }
}))

beforeEach(() => {
  session.token = null
  session.select.mockClear()
})

it('병원 진입 화면에서 연결되지 않은 로그인을 활성화하지 않는다', () => {
  const { container } = render(<HospitalPortal />)
  expect(container.querySelector('.hospital-theme')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: '병원 직원 로그인' })).toBeDisabled()
  expect(screen.getByText(/로그인 서비스 연결 전/)).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: /전체 전달 대기/ })).not.toBeInTheDocument()
})

it('직원 로그인 후 기존 담당 환자와 전달 대기 전환을 유지한다', () => {
  session.token = 'test-only-session'
  render(<HospitalPortal />)
  expect(screen.getByRole('heading', { name: '가상 환자' })).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: /가상 환자/ }))
  expect(session.select).toHaveBeenCalledWith('fixture')
  fireEvent.click(screen.getByRole('button', { name: /전체 전달 대기/ }))
  expect(screen.getByRole('heading', { name: '전체 전달 대기' })).toBeInTheDocument()
})
