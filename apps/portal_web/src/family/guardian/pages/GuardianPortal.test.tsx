import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { GuardianPortal } from './GuardianPortal'
const mocks=vi.hoisted(()=>({targets:vi.fn(),list:vi.fn(),withdraw:vi.fn(),submit:vi.fn(),api:{}}))
vi.mock('../../../shared/auth/AuthContext',()=>({useAuth:()=>({api:mocks.api,token:'guardian-token'})}))
vi.mock('../../../shared/api/familyMaterials',async original=>({...await original<typeof import('../../../shared/api/familyMaterials')>(),materialApi:{targets:mocks.targets,list:mocks.list,withdraw:mocks.withdraw}}))
vi.mock('../../studio/api',()=>({studioRequest:mocks.submit}))
beforeEach(()=>{vi.clearAllMocks();mocks.targets.mockResolvedValue([{patient_id:'one',encounter_id:'admission',patient_name:'김하늘',hospital_ref:'TEST-FAVILIUM',relationship:'딸'}]);mocks.list.mockResolvedValue([])})
it('대상 환자와 병원을 표시하고 전송 동의 후 현재 자료를 보낸다',async()=>{
 mocks.submit.mockResolvedValue({material_id:'material-1'})
 render(<GuardianPortal/>);expect(await screen.findByText('김하늘')).toBeVisible()
 expect(screen.getByText(/TEST-FAVILIUM/)).toBeVisible()
 expect(screen.getByRole('button',{name:'현재 자료 보내기'})).toBeDisabled()
 fireEvent.click(screen.getByRole('checkbox'))
 fireEvent.click(screen.getByRole('button',{name:'현재 자료 보내기'}))
 await waitFor(()=>expect(mocks.submit).toHaveBeenCalledWith('/hospital-materials','POST',{patient_id:'one',encounter_id:'admission',sharing_consent:true}))
 expect(screen.queryByRole('button',{name:'새 기억'})).not.toBeInTheDocument()
})
it('연결 조회 실패를 빈 성공 목록으로 바꾸지 않고 재시도한다',async()=>{
 mocks.targets.mockRejectedValueOnce(new Error('offline'))
 render(<GuardianPortal/>);expect(await screen.findByRole('alert')).toHaveTextContent('병원 연결과 제출 자료를 확인하지 못했습니다.')
 expect(screen.queryByText(/확인된 입원 연결이 없습니다/)).not.toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'다시 조회'}));expect(await screen.findByText('김하늘')).toBeVisible()
})
it('성공적으로 빈 결과를 조회한 경우에만 연결 없음을 표시한다',async()=>{
 mocks.targets.mockResolvedValue([]);render(<GuardianPortal/>);expect(await screen.findByText(/확인된 입원 연결이 없습니다/)).toBeVisible()
})
