import { describe, expect, it, vi } from 'vitest'
import { RequestEpoch, retainOwnedStream } from './requestEpoch'

describe('비동기 요청 소유권', () => {
  it('새 선택과 로그아웃 이후 이전 응답을 거부한다', () => {
    const epoch = new RequestEpoch(); const patientA = epoch.begin()
    expect(epoch.owns(patientA)).toBe(true)
    const patientB = epoch.begin()
    expect(epoch.owns(patientA)).toBe(false); expect(epoch.owns(patientB)).toBe(true)
    epoch.invalidate(); expect(epoch.owns(patientB)).toBe(false)
  })
  it('소유권이 끝난 뒤 도착한 마이크 스트림을 즉시 닫는다', () => {
    const epoch = new RequestEpoch(); const owner = epoch.begin(); const stop = vi.fn(); epoch.invalidate()
    expect(retainOwnedStream(epoch, owner, { getTracks: () => [{ stop }] } as unknown as MediaStream)).toBe(false)
    expect(stop).toHaveBeenCalledOnce()
  })
})
