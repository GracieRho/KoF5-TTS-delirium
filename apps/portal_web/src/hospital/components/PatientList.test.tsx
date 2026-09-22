import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { PatientList } from './PatientList'

const patients = [{ patient_id: '1', ehr_patient_ref: 'P-100', staff_display_name: '김환자', encounter_id: 'e', ward_ref: '5병동', room_ref: '501', bed_ref: 'A' }, { patient_id: '2', ehr_patient_ref: 'P-200', staff_display_name: '이환자' }]
describe('담당 환자 목록', () => {
  it('모바일과 데스크톱에서 같은 검색·선택 흐름을 제공한다', () => {
    const select = vi.fn(); render(<PatientList patients={patients} onSelect={select}/>)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: '5병동' } })
    expect(screen.getByText('김환자')).toBeInTheDocument(); expect(screen.queryByText('이환자')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /김환자/ })); expect(select).toHaveBeenCalledWith('1')
  })
})
