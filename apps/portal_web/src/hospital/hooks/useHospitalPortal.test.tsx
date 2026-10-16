import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useHospitalPortal } from './useHospitalPortal'
import { hospitalApi } from '../api/hospitalApi'
const auth = vi.hoisted(() => ({ api: {}, token: 'staff' }))
vi.mock('../../shared/auth/AuthContext', () => ({ useAuth: () => auth }))
vi.mock('../api/hospitalApi', () => ({ hospitalApi: { patients: vi.fn(), readiness: vi.fn(), queue: vi.fn(), facts: vi.fn(), messages: vi.fn() } }))
const patient = { patient_id: 'p', ehr_patient_ref: 'TEST', staff_display_name: '가상 환자' }
const fact = { fact_id: 'f', category: 'hospital', content: '병원 안내', encounter_id: 'e' }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r }); return { promise, resolve } }
beforeEach(() => {
  vi.resetAllMocks(); auth.token = 'staff'
  vi.mocked(hospitalApi.patients).mockResolvedValue([patient]); vi.mocked(hospitalApi.readiness).mockResolvedValue([]); vi.mocked(hospitalApi.queue).mockResolvedValue([])
  vi.mocked(hospitalApi.facts).mockResolvedValue([fact]); vi.mocked(hospitalApi.messages).mockResolvedValue([])
})
describe('hospital read ownership', () => {
  it('independently shows patients, pending readiness, failed queue, and retry', async () => {
    const pending = deferred<[]>()
    vi.mocked(hospitalApi.readiness).mockReturnValueOnce(pending.promise)
    vi.mocked(hospitalApi.queue).mockRejectedValueOnce(new Error('network'))
    const { result } = renderHook(() => useHospitalPortal())
    await waitFor(() => expect(result.current.loadState.queue).toBe('error'))
    expect(result.current.patients).toEqual([patient]); expect(result.current.loadState.patients).toBe('ready')
    expect(result.current.loadState.readiness).toBe('loading'); expect(result.current.errors.queue).toContain('읽지 못했습니다')
    await act(async () => { pending.resolve([]); await result.current.refresh() })
    expect(result.current.loadState.queue).toBe('ready'); expect(result.current.errors.queue).toBe('')
  })
  it('retains facts after message failure without cancelling pending patient loading', async () => {
    const pending = deferred<typeof patient[]>()
    vi.mocked(hospitalApi.patients).mockReturnValueOnce(pending.promise)
    vi.mocked(hospitalApi.messages).mockRejectedValueOnce(new Error('network'))
    const { result } = renderHook(() => useHospitalPortal())
    await act(async () => { await result.current.select('p') })
    expect(result.current.facts).toEqual([fact]); expect(result.current.loadState.messages).toBe('error')
    await act(async () => { pending.resolve([patient]) })
    expect(result.current.selected).toEqual(patient)
    await act(async () => { await result.current.reloadSelected() })
    expect(result.current.loadState.messages).toBe('ready')
  })
  it('discards late detail results after a session change', async () => {
    const pending = deferred<typeof fact[]>()
    vi.mocked(hospitalApi.facts).mockReturnValueOnce(pending.promise)
    const { result, rerender } = renderHook(() => useHospitalPortal())
    await waitFor(() => expect(result.current.loadState.patients).toBe('ready'))
    let initial!: Promise<void>
    act(() => { initial = result.current.select('p') })
    auth.token = ''; rerender()
    await act(async () => { pending.resolve([fact]); await initial })
    expect(result.current.facts).toEqual([]); expect(result.current.patients).toEqual([])
  })
})
