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
it('화면 설명은 기본적으로 숨기고 미확인 기록 상태는 유지한다',()=>{
 render(<HospitalPortal />)
 expect(screen.queryByText('입원 환자의 변화와 오늘 확인할 일을 함께 봅니다.')).not.toBeInTheDocument()
 expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
 expect(screen.getByText('기록 미확인 1명')).toBeVisible()
 fireEvent.click(screen.getByRole('button',{name:'돌봄 현황 도움말'}))
 expect(screen.getByRole('tooltip')).toHaveTextContent('돌봄 지표는 열람 가능한 0명의 기록 기준입니다.')
})
