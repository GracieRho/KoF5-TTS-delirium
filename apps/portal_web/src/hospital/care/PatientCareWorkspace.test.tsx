import {render,screen} from '@testing-library/react'
import {expect,it,vi} from 'vitest'
import {PatientCareWorkspace} from './PatientCareWorkspace'
import {EMPTY_CARE,type CareData} from './api'
import type {useHospitalCare} from './useHospitalCare'
vi.mock('../../shared/auth/AuthContext',()=>({useAuth:()=>({api:null,token:'staff'})}))
vi.mock('../components/FamilyMaterialReview',()=>({FamilyMaterialReview:()=>null}))
const patient={patient_id:'patient',encounter_id:'encounter',staff_display_name:'김하늘',ehr_patient_ref:'TEST-001'}
const base={patient_id:'patient',encounter_id:'encounter'}
function care(data:Partial<CareData>){return {data:{...EMPTY_CARE,permissions:[{...base,can_read:true,can_document:true}],...data},loading:false,error:'',notice:'',busy:false,refresh:vi.fn(),save:vi.fn()} as unknown as ReturnType<typeof useHospitalCare>}
it('미완료·보류 돌봄을 먼저 표시하고 수행 기록은 접는다',()=>{
 const tasks=[{...base,task_id:'done',title:'어제 수행',due_at:'2026-10-14',status:'completed',category:'sensory'}, {...base,task_id:'held',title:'보류 업무',due_at:'2026-10-15',status:'held',category:'sensory'},{...base,task_id:'next',title:'내일 업무',due_at:'2026-10-17',status:'open',category:'sensory'}] as CareData['tasks']
 render(<PatientCareWorkspace patient={patient} care={care({tasks})} facts={[]} messages={[]} tab="plan" onTabChange={vi.fn()} onBack={vi.fn()}/>)
 expect(screen.getByRole('heading',{name:'보류 업무'})).toBeVisible()
 expect(screen.getByRole('heading',{name:'내일 업무'})).toBeVisible()
 expect(screen.getByText('어제 수행')).not.toBeVisible()
 expect(screen.getByText('수행 이력 1건')).toBeVisible()
})
it('취소된 음성 계획은 이력에 접고 대상 기록으로 열면 펼친다',()=>{
 const plans=[{...base,schedule_id:'cancelled',script:'취소한 계획',purpose:'orientation',scheduled_at:'2026-10-14',status:'cancelled',duration_minutes:5},{...base,schedule_id:'planned',script:'예정 계획',purpose:'orientation',scheduled_at:'2026-10-17',status:'planned',duration_minutes:5}] as CareData['plans']
 const props={patient,care:care({plans}),facts:[],messages:[],tab:'voice' as const,onTabChange:vi.fn(),onBack:vi.fn()}
 const {rerender}=render(<PatientCareWorkspace {...props}/>)
 expect(screen.getByText('예정 계획')).toBeVisible()
 expect(screen.getByText('취소한 계획')).not.toBeVisible()
 rerender(<PatientCareWorkspace {...props} record="cancelled"/>)
 expect(screen.getByText('취소한 계획')).toBeVisible()
})
