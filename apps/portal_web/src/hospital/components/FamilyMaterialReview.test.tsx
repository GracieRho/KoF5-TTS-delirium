import {render,screen} from '@testing-library/react'
import {beforeEach,expect,it,vi} from 'vitest'
import {FamilyMaterialReview} from './FamilyMaterialReview'
const mocks=vi.hoisted(()=>({list:vi.fn(),bindings:vi.fn(),api:{}}))
vi.mock('../../shared/auth/AuthContext',()=>({useAuth:()=>({api:mocks.api,token:'staff'})}))
vi.mock('../../shared/api/familyMaterials',async original=>({...await original<typeof import('../../shared/api/familyMaterials')>(),materialApi:{list:mocks.list,bindings:mocks.bindings}}))
const patient={patient_id:'patient',encounter_id:'encounter',staff_display_name:'가상 환자',ehr_patient_ref:'TEST'}
beforeEach(()=>{vi.clearAllMocks();mocks.bindings.mockResolvedValue([])})
it('보호자가 created를 제출해도 공급자 등록을 검증한 것처럼 표시하지 않는다',async()=>{
 mocks.list.mockResolvedValue([{material_id:'one',revision:1,profile:{guardian_name:'가상 보호자',relationship:'딸'},memories:[],voice_status:'created',status:'pending',submitted_at:'2026-10-16T00:00:00Z'}])
 render(<FamilyMaterialReview patient={patient} plans={[]} writable/>)
 expect(await screen.findByText(/보호자 제출 음성 상태 · 등록됨 · 등록 여부 미검증/)).toBeVisible()
 expect(screen.getByText('검토 대기')).toBeVisible()
})
it('자료 조회 실패 시 빈 목록 대신 지속 오류를 표시한다',async()=>{
 mocks.list.mockRejectedValue(new Error('offline'));render(<FamilyMaterialReview patient={patient} plans={[]} writable/>)
 expect(await screen.findByRole('alert')).toHaveTextContent('가족 자료를 확인하지 못했습니다.')
 expect(screen.queryByText('보호자가 보낸 가족 자료가 없습니다.')).not.toBeInTheDocument()
})
