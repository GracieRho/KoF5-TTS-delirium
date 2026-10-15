import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { HospitalPortal } from './HospitalPortal'
vi.mock('../../shared/auth/AuthContext',()=>({useAuth:()=>({token:'staff',api:null,userId:'staff',signOut:vi.fn()})}))
vi.mock('../hooks/useHospitalPortal',()=>({useHospitalPortal:()=>{const patient={patient_id:'fixture',ehr_patient_ref:'TEST-001',staff_display_name:'가상 환자',encounter_id:'test-encounter',ward_ref:'시험병동'};return {api:null,token:'staff',patients:[patient],selected:patient,queue:[],facts:[],messages:[],readiness:[],status:'',select:vi.fn()}}}))
vi.mock('../care/useHospitalCare',async()=>{const {EMPTY_CARE}=await import('../care/api');return{useHospitalCare:()=>({data:EMPTY_CARE,loading:false,error:'',notice:'',busy:false,refresh:vi.fn(),save:vi.fn()})}})
it('병원 메뉴에 보호자 링크와 중복 공간 이동을 넣지 않는다',()=>{
 render(<HospitalPortal />)
 expect(screen.getByRole('heading',{name:'병동 돌봄 현황'})).toBeInTheDocument()
 expect(screen.getAllByRole('link')).toHaveLength(1)
 fireEvent.click(screen.getByRole('button',{name:'음성·전달 일정'}))
 expect(screen.getByRole('heading',{name:'음성·전달 일정'})).toBeInTheDocument()
})
it('일반 가상 환자도 다섯 개 돌봄 작업 탭을 갖는다',()=>{
 render(<HospitalPortal />)
 fireEvent.click(screen.getByRole('button',{name:'가상 환자 돌봄 열기'}))
 expect(screen.getByRole('heading',{name:'가상 환자'})).toBeInTheDocument()
 expect(screen.getAllByRole('tab')).toHaveLength(5)
 fireEvent.click(screen.getByRole('tab',{name:/돌봄 계획/}))
 expect(screen.getByText('돌봄 열람 권한 확인이 필요합니다.')).toBeInTheDocument()
 expect(screen.queryByRole('button',{name:'돌봄 업무 추가'})).not.toBeInTheDocument()
})
