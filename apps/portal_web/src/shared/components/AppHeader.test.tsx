import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { AppHeader } from './AppHeader'

describe('공통 포털 셸', () => {
  it('병원 브랜드는 병원 안에만 머문다', () => {
    const { container } = render(<AppHeader area="병원"/>)
    expect(container.querySelector('header')).toHaveClass('hospital-header')
    expect(screen.getAllByRole('link')).toHaveLength(1)
    expect(screen.getByRole('link', { name: 'Favilium' })).toHaveAttribute('href', '/hospital')
  })

  it('보호자 브랜드는 스튜디오 안에만 머문다', () => {
    render(<AppHeader area="보호자"/>)
    expect(screen.getByRole('link', { name: 'Favilium' })).toHaveAttribute('href', '/studio')
    expect(screen.getAllByRole('link')).toHaveLength(1)
  })
})
