import { fireEvent,render,screen,waitFor } from '@testing-library/react'
import { expect,it,vi } from 'vitest'
import { CareNoteForm,CareTaskForm,VoicePlanForm } from './CareForms'
import { careApi,EMPTY_CARE,type CareData } from './api'
import { patientCare,assessmentLabel } from './metrics'
const patient={patient_id:'patient',encounter_id:'encounter',staff_display_name:'김하늘',ehr_patient_ref:'TEST-001'}
it('평가를 미리 음성으로 채우지 않고 실제 입력한 결과를 저장한다',async()=>{
 const save=vi.fn().mockResolvedValue(undefined)
 const {container}=render(<CareNoteForm patient={patient} busy={false} kind="assessment" save={save}/>)
 expect(screen.getByRole('combobox',{name:'기록된 결과'})).toHaveTextContent('결과 선택')
 fireEvent.click(screen.getByRole('combobox',{name:'기록된 결과'}))
 fireEvent.click(screen.getByRole('option',{name:'평가 불가'}))
 fireEvent.change(screen.getByLabelText('평가 불가 사유와 관찰 내용'),{target:{value:'피로를 표현해 평가를 마치지 못했습니다.'}})
 fireEvent.submit(container.querySelector('form')!)
 await waitFor(()=>expect(save).toHaveBeenCalledWith(expect.objectContaining({kind:'assessment',result:'unable',score:null,tool:'4AT',patient_id:'patient',encounter_id:'encounter'})))
})
it('돌봄 업무는 담당자와 확인 기한을 함께 보낸다',async()=>{
 const save=vi.fn().mockResolvedValue(undefined)
 const {container}=render(<CareTaskForm patient={patient} busy={false} save={save}/>)
 fireEvent.change(screen.getByLabelText('수행할 일'),{target:{value:'안경 착용 확인'}})
 fireEvent.submit(container.querySelector('form')!)
 await waitFor(()=>expect(save).toHaveBeenCalledWith(expect.objectContaining({title:'안경 착용 확인',owner_label:'병동팀',due_at:expect.any(String)})))
})
it('동시 수정으로 0행이 돌아오면 성공으로 표시하지 않는다',async()=>{
 const request=vi.fn().mockResolvedValue([])
 await expect(careApi.write({request} as never,'token','care_task',{status:'completed'},'task-id',3)).rejects.toThrow('다른 직원')
 expect(request).toHaveBeenCalledWith('/rest/v1/care_task?task_id=eq.task-id&version=eq.3',expect.objectContaining({returnRow:true,method:'PATCH'}))
})
it('같은 입원 기록만 집계하고 주의 기록 처리와 정정을 반영한다',()=>{
 const data={...EMPTY_CARE,permissions:[{patient_id:'patient',encounter_id:'encounter',can_read:true,can_document:true}],notes:[{note_id:'concern',patient_id:'patient',encounter_id:'encounter',kind:'concern',observed_at:'2026-10-15'}, {note_id:'resolution',related_note_id:'concern',patient_id:'patient',encounter_id:'encounter',kind:'resolution',observed_at:'2026-10-15'}, {note_id:'old',patient_id:'patient',encounter_id:'old-encounter',kind:'assessment',observed_at:'2026-10-15'}]} as CareData
 const rows=patientCare(data,patient)
 expect(rows.concerns).toHaveLength(0);expect(rows.assessment).toBeUndefined()
 expect(assessmentLabel(rows.assessment)).toBe('평가 기록 없음')
})

it('정정만으로 주의가 사라지거나 과거 음성 평가가 최신으로 올라오지 않는다',()=>{
 const base={patient_id:'patient',encounter_id:'encounter'}
 const data={...EMPTY_CARE,notes:[
  {...base,note_id:'old-negative',kind:'assessment',result:'negative',observed_at:'2026-10-14'},
  {...base,note_id:'positive',kind:'assessment',result:'positive',observed_at:'2026-10-15'},
  {...base,note_id:'positive-correction',kind:'correction',related_note_id:'positive',observed_at:'2026-10-16'},
  {...base,note_id:'concern',kind:'concern',observed_at:'2026-10-15'},
  {...base,note_id:'concern-correction',kind:'correction',related_note_id:'concern',observed_at:'2026-10-16'}
 ]} as CareData
 const rows=patientCare(data,patient)
 expect(rows.assessment?.note_id).toBe('positive');expect(rows.concerns).toHaveLength(1)
 const resolved={...data,notes:[...data.notes,{...base,note_id:'resolution',kind:'resolution',related_note_id:'concern',observed_at:'2026-10-16'},{...base,note_id:'resolution-correction',kind:'correction',related_note_id:'resolution',observed_at:'2026-10-17'}]} as CareData
 expect(patientCare(resolved,patient).concerns).toHaveLength(0)
})

it('음성 계획은 날짜 컨트롤에 실제 표시된 변경 시각을 저장한다',async()=>{
 const save=vi.fn().mockResolvedValue(undefined)
 const {container}=render(<VoicePlanForm patient={patient} busy={false} save={save}/>)
 const date=screen.getByLabelText('예정 시각') as HTMLInputElement
 date.value='2026-10-16T10:30'
 fireEvent.change(screen.getByLabelText('안내할 내용'),{target:{value:'가족 사진 이야기'}})
 fireEvent.submit(container.querySelector('form')!)
 await waitFor(()=>expect(save).toHaveBeenCalledWith(expect.objectContaining({scheduled_at:new Date('2026-10-16T10:30').toISOString()})))
})
