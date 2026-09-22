import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { HospitalTabs } from './HospitalTabs'

describe('병원 업무 탭', () => {
  it('화살표 키로 다음 탭을 선택하고 패널을 연결한다', () => {
    const change = vi.fn(); render(<HospitalTabs value="summary" onChange={change} synthetic/>)
    const tab = screen.getByRole('tab', { name: '입원 정보' }); expect(tab).toHaveAttribute('aria-controls', 'hospital-panel-summary'); expect(tab).toHaveAttribute('tabindex', '0')
    fireEvent.keyDown(tab, { key: 'ArrowRight' }); expect(change).toHaveBeenCalledWith('queue')
  })
})
