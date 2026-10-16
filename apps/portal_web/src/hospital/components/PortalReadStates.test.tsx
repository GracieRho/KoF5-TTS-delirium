import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { PatientSummary } from './PatientSummary'
import { QueueList } from './QueueList'
describe('persistent hospital read states', () => {
  it('offers retry for errors and never calls loading/error records empty', () => {
    const retry = vi.fn()
    render(<PatientSummary facts={[]} messages={[]} states={{ facts: 'error', messages: 'loading' }} onRetry={retry}/>)
    expect(screen.getByRole('alert')).toHaveTextContent('직원 승인 사실을 읽지 못했습니다.')
    expect(screen.getByRole('status')).toHaveTextContent('불러오는 중'); expect(screen.queryByText(/없습니다/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '다시 시도' })); expect(retry).toHaveBeenCalledOnce()
  })
  it('shows queue empty only after successful read', () => {
    const { rerender } = render(<QueueList messages={[]} patients={[]} state="error"/>)
    expect(screen.getByRole('alert')).toBeInTheDocument(); expect(screen.queryByText('현재 전달 대기 메시지가 없습니다.')).not.toBeInTheDocument()
    rerender(<QueueList messages={[]} patients={[]} state="ready"/>); expect(screen.getByText('현재 전달 대기 메시지가 없습니다.')).toBeInTheDocument()
  })
  it('opens the selected queue record', () => {
    const open = vi.fn(), message = { message_id: 'm', patient_id: 'p', encounter_id: 'e', approved_text: '곧 면회합니다.', due_at: '2026-10-16T00:00:00Z', delivery_status: 'pending' }
    render(<QueueList messages={[message]} patients={[{ patient_id: 'p', ehr_patient_ref: 'TEST', staff_display_name: '환자' }]} onOpen={open}/>)
    fireEvent.click(screen.getByRole('button', { name: '메시지 확인' })); expect(open).toHaveBeenCalledWith(message)
  })
})
