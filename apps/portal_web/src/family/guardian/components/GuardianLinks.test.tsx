import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { GuardianLinks } from './GuardianLinks'

describe('보호자 연결 선택', () => {
  it('유효한 연결을 선택 옵션으로 표시한다', () => {
    render(<GuardianLinks links={[{
      patient_id: '00000000-0000-4000-8000-000000000975',
      relationship: '딸',
      access_status: 'verified',
      effective_at: '2026-01-01T00:00:00Z',
      expires_at: null,
    }]} selected="00000000-0000-4000-8000-000000000975" onSelect={vi.fn()}/>)

    expect(screen.getByRole('option', { name: '딸 · 000975' })).toBeInTheDocument()
  })
})
