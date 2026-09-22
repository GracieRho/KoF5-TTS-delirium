import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { VoiceTrial } from './VoiceTrial'

vi.mock('../hooks/useGuardianVoiceTrial', () => ({ useGuardianVoiceTrial: () => ({ remote: null, samples: [], recording: false, busy: false, status: '준비', ready: true, ownConfirmed: false, setOwnConfirmed: vi.fn(), start: vi.fn(), stop: vi.fn(), enroll: vi.fn(), refresh: vi.fn(), mutate: vi.fn() }) }))

describe('보호자 음성 시험', () => {
  it('본인 음성 확인 전 녹음과 업로드를 잠근다', () => {
    render(<VoiceTrial patientId="00000000-0000-4000-8000-000000000975" token="token"/>)
    expect(screen.getByRole('checkbox', { name: /내 목소리만/ })).not.toBeChecked(); expect(screen.getByRole('button', { name: '다음 합성 샘플 녹음' })).toBeDisabled(); expect(screen.getByRole('button', { name: '세 샘플 합성 업로드' })).toBeDisabled()
  })
})
