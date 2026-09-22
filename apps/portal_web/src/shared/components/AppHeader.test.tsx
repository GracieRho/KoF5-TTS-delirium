import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { AppHeader } from './AppHeader'

describe('공통 포털 셸', () => {
  it('병원 화면에 데스크톱 rail 클래스와 보호자 이동 경로를 제공한다', () => {
    const { container } = render(<AppHeader area="병원"/>)
    expect(container.querySelector('header')).toHaveClass('hospital-header')
    expect(screen.getByRole('link', { name: '보호자 기억' })).toHaveAttribute('href', '/guardian')
  })

  it('보호자 화면은 동일한 브랜드와 병원 이동 경로를 제공한다', () => {
    render(<AppHeader area="보호자"/>)
    expect(screen.getByRole('link', { name: /Familiar Voice/ })).toHaveAttribute('href', '/guardian')
    expect(screen.getByRole('link', { name: '병원 업무' })).toHaveAttribute('href', '/hospital')
  })
})
