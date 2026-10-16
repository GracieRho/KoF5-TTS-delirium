import { describe, expect, it } from 'vitest'
import { validLink } from './guardianApi'

describe('보호자 연결', () => {
  it('검증 기간 안의 연결만 현재 연결로 본다', () => {
    expect(validLink({ patient_id: 'p', relationship: '딸', access_status: 'verified', effective_at: '2026-01-01T00:00:00Z', expires_at: '2027-01-01T00:00:00Z' }, Date.parse('2026-09-22T00:00:00Z'))).toBe(true)
    expect(validLink({ patient_id: 'p', relationship: '딸', access_status: 'pending', effective_at: '2026-01-01T00:00:00Z' }, Date.parse('2026-09-22T00:00:00Z'))).toBe(false)
  })
})
