import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { HospitalPortal } from './HospitalPortal'
const fixture=vi.hoisted(()=>({plans:[] as unknown[],notes:[] as unknown[]}))
vi.mock('../../shared/auth/AuthContext',()=>({useAuth:()=>({token:'staff',api:null,userId:'staff',signOut:vi.fn()})}))
vi.mock('../hooks/useHospitalPortal',()=>({useHospitalPortal:()=>{const patient={patient_id:'fixture',ehr_patient_ref:'TEST-001',staff_display_name:'가상 환자',encounter_id:'test-encounter',ward_ref:'시험병동'};return {api:null,token:'staff',patients:[patient],selected:patient,queue:[],facts:[],messages:[],readiness:[],status:'',loadState:{patients:'ready',readiness:'ready',queue:'ready',facts:'ready',messages:'ready'},errors:{},reloadSelected:vi.fn(),refresh:vi.fn(),select:vi.fn()}}}))
vi.mock('../care/useHospitalCare',async()=>{const {EMPTY_CARE}=await import('../care/api');return{useHospitalCare:()=>({data:{...EMPTY_CARE,plans:fixture.plans,notes:fixture.notes},loading:false,error:'',notice:'',busy:false,refresh:vi.fn(),save:vi.fn()})}})
beforeEach(()=>{window.history.replaceState(null,'','/hospital');fixture.plans=[];fixture.notes=[]})
it('병원 메뉴에 보호자 링크와 중복 공간 이동을 넣지 않는다',()=>{
 render(<HospitalPortal />)
 expect(screen.getByRole('heading',{name:'담당 환자'})).toBeInTheDocument()
 expect(screen.getAllByRole('link')).toHaveLength(1)
 fireEvent.click(screen.getByRole('button',{name:'음성 업무'}))
 expect(screen.getByRole('heading',{name:'음성 업무'})).toBeInTheDocument()
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

it('검색·필터와 환자 작업 탭을 주소에 보존하고 목록 복귀 시 복원한다',()=>{
 render(<HospitalPortal />)
 fireEvent.change(screen.getByRole('searchbox'),{target:{value:'가상'}})
 fireEvent.click(screen.getByRole('button',{name:'가상 환자 돌봄 열기'}))
 fireEvent.click(screen.getByRole('tab',{name:'음성 준비·계획'}))
 expect(window.location.search).toContain('patient=fixture')
 expect(window.location.search).toContain('tab=voice')
 fireEvent.click(screen.getByRole('button',{name:'← 환자 목록'}))
 expect(screen.getByRole('searchbox')).toHaveValue('가상')
})
it('주소에서 환자 작업 탭을 복원하고 평가 버튼을 다른 탭에 반복하지 않는다',()=>{
 window.history.replaceState(null,'','/hospital?view=patients&patient=fixture&tab=voice&record=plan-1')
 render(<HospitalPortal />)
 expect(screen.getByRole('tab',{name:'음성 준비·계획'})).toHaveAttribute('aria-selected','true')
 expect(screen.queryByRole('button',{name:'평가 기록 추가'})).not.toBeInTheDocument()
})
it('음성 계획과 승인 메시지는 한 번에 하나만 표시한다',()=>{
 render(<HospitalPortal />)
 fireEvent.click(screen.getByRole('button',{name:'음성 업무'}))
 expect(screen.getByRole('heading',{name:/가족 음성 사용 계획/})).toBeInTheDocument()
 expect(screen.queryByRole('heading',{name:/병원 승인 안내/})).not.toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'승인 메시지 0'}))
 expect(screen.queryByRole('heading',{name:/가족 음성 사용 계획/})).not.toBeInTheDocument()
 expect(screen.getByRole('heading',{name:/병원 승인 안내/})).toBeInTheDocument()
})

it('전역 음성 계획에서 정확한 환자 음성 탭과 계획을 연다',()=>{
 fixture.plans=[{schedule_id:'target-plan',patient_id:'fixture',encounter_id:'test-encounter',status:'planned',purpose:'orientation',script:'안내 내용',scheduled_at:'2026-10-16T10:00:00Z',duration_minutes:5,owner_label:'병동팀'}]
 render(<HospitalPortal />)
 fireEvent.click(screen.getByRole('button',{name:'음성 업무'}))
 fireEvent.click(screen.getByRole('button',{name:'환자에서 관리'}))
 expect(screen.getByRole('tab',{name:'음성 준비·계획'})).toHaveAttribute('aria-selected','true')
 expect(window.location.search).toContain('record=target-plan')
})
it('전역 인계 기록에서 정확한 환자 인계 탭과 기록을 연다',()=>{
 fixture.notes=[{note_id:'target-note',patient_id:'fixture',encounter_id:'test-encounter',kind:'handoff',summary:'인계 내용',observed_at:'2026-10-16T10:00:00Z'}]
 render(<HospitalPortal />)
 fireEvent.click(screen.getByRole('button',{name:'인계·주의 사항'}))
 fireEvent.click(screen.getByRole('button',{name:'환자 기록 열기'}))
 expect(screen.getByRole('tab',{name:'인계·이력'})).toHaveAttribute('aria-selected','true')
 expect(window.location.search).toContain('record=target-note')
})
