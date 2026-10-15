import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { GuardianPortal } from './GuardianPortal'
HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', '') }
HTMLDialogElement.prototype.close = function () { this.removeAttribute('open') }
const mocks=vi.hoisted(()=>({targets:vi.fn(),list:vi.fn(),withdraw:vi.fn(),submit:vi.fn(),api:{}}))
vi.mock('../../../shared/auth/AuthContext',()=>({useAuth:()=>({api:mocks.api,token:'guardian-token'})}))
vi.mock('../../../shared/api/familyMaterials',async original=>({...await original<typeof import('../../../shared/api/familyMaterials')>(),materialApi:{targets:mocks.targets,list:mocks.list,withdraw:mocks.withdraw}}))
vi.mock('../../studio/api',()=>({studioRequest:mocks.submit}))
beforeEach(()=>{vi.clearAllMocks();mocks.targets.mockResolvedValue([{patient_id:'one',encounter_id:'admission',patient_name:'김하늘',hospital_ref:'TEST-FAVILIUM',relationship:'딸'}]);mocks.list.mockResolvedValue([]);mocks.submit.mockResolvedValue({profile:{guardian_name:'김서연',patient_alias:'김하늘',relationship:'딸',address_as:'아빠'},memories:[{id:'memory',title:'산책',category:'story',content:'가상 산책 기억'}],voice:{status:'none'}})})
it('대상 환자와 병원을 표시하고 전송 동의 후 현재 자료를 보낸다',async()=>{
 mocks.submit.mockImplementation((path:string)=>Promise.resolve(path==='/state'?{profile:{guardian_name:'김서연',patient_alias:'김하늘',relationship:'딸',address_as:'아빠'},memories:[{id:'memory',title:'산책',category:'story',content:'가상 산책 기억'}],voice:{status:'none'}}:{material_id:'material-1'}))
 render(<GuardianPortal/>);expect(await screen.findByText('김하늘')).toBeVisible()
 expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'자료 보내기'}))
 expect(await screen.findByText('받는 대상 · 김하늘')).toBeVisible()
 await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled())
 expect(screen.getByRole('button',{name:'동의하고 보내기'})).toBeDisabled()
 fireEvent.click(screen.getByRole('checkbox'))
 fireEvent.click(screen.getByRole('button',{name:'동의하고 보내기'}))
 await waitFor(()=>expect(mocks.submit).toHaveBeenCalledWith('/hospital-materials','POST',{patient_id:'one',encounter_id:'admission',sharing_consent:true}))
 expect(screen.queryByRole('button',{name:'새 기억'})).not.toBeInTheDocument()
})
it('연결 조회 실패를 빈 성공 목록으로 바꾸지 않고 재시도한다',async()=>{
 mocks.targets.mockRejectedValueOnce(new Error('offline'))
 render(<GuardianPortal/>);expect(await screen.findByRole('alert')).toHaveTextContent('병원 연결과 제출 자료를 확인하지 못했습니다.')
 expect(screen.queryByText(/확인된 입원 연결이 없습니다/)).not.toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'다시 시도'}));expect(await screen.findByText('김하늘')).toBeVisible()
})
it('성공적으로 빈 결과를 조회한 경우에만 연결 없음을 표시한다',async()=>{
 mocks.targets.mockResolvedValue([]);render(<GuardianPortal/>);expect(await screen.findByText(/확인된 입원 연결이 없습니다/)).toBeVisible()
})

it('전송 시트를 닫았다가 다시 열면 동의를 다시 받는다',async()=>{
 render(<GuardianPortal/>);fireEvent.click(await screen.findByRole('button',{name:'자료 보내기'}))
 await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled());fireEvent.click(screen.getByRole('checkbox'))
 fireEvent.click(screen.getByRole('button',{name:'가족 자료 보내기 닫기'}))
 fireEvent.click(screen.getByRole('button',{name:'자료 보내기'}))
 await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled());expect(screen.getByRole('checkbox')).not.toBeChecked()
})
it('최신 제출을 먼저 보여주고 사본의 소개·기억·미검증 음성 상태를 확인한다',async()=>{
 const material={material_id:'one',patient_id:'one',encounter_id:'admission',revision:2,status:'approved',submitted_at:'2026-10-16T00:00:00Z',review_note:'검토한 의견',profile:{guardian_name:'김서연',patient_alias:'김하늘',relationship:'딸',address_as:'아빠'},memories:[{id:'m',title:'산책',category:'avoid',content:'피할 가상 이야기'}],voice_status:'created'}
 mocks.list.mockResolvedValue([{...material,revision:1,material_id:'old',status:'superseded'},material])
 render(<GuardianPortal/>);expect(await screen.findByText('검토 완료')).toBeVisible()
 expect(screen.getByText('이전 버전')).not.toBeVisible()
 expect(screen.queryByRole('button',{name:'공유 철회'})).not.toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'보낸 자료 보기'}))
 expect(await screen.findByText('가족 소개')).toBeVisible();expect(screen.getByText('아빠',{exact:false})).toBeVisible()
 expect(screen.getByText('피해야 할 이야기')).toBeVisible();expect(screen.getByText('등록됨 · 등록 여부 미검증')).toBeVisible()
 fireEvent.click(screen.getByRole('button',{name:'공유 철회'}));expect(screen.getByRole('button',{name:'이 버전 공유 철회'})).toBeVisible()
 expect(mocks.withdraw).not.toHaveBeenCalled()
})
it('자료 전송 실패는 시트 안에서 보이고 닫을 수 있다',async()=>{
 const preview={profile:{guardian_name:'김서연',patient_alias:'김하늘',relationship:'딸',address_as:'아빠'},memories:[{id:'m',title:'산책',category:'story',content:'가상 기억'}],voice:{status:'none'}}
 mocks.submit.mockImplementation((path:string)=>path==='/state'?Promise.resolve(preview):Promise.reject(new Error('전송 실패')))
 render(<GuardianPortal/>);fireEvent.click(await screen.findByRole('button',{name:'자료 보내기'}))
 await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled());fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'동의하고 보내기'}))
 await waitFor(()=>expect(screen.getByRole('dialog')).toHaveTextContent('전송 실패'))
 fireEvent.click(screen.getByRole('button',{name:'가족 자료 보내기 닫기'}));expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})
it.each([['pending','검토 대기'],['rejected','보완 요청'],['withdrawn','공유 철회']])('최신 %s 제출 상태를 숨기지 않는다',async(status,label)=>{
 mocks.list.mockResolvedValue([{material_id:'one',patient_id:'one',encounter_id:'admission',revision:1,status,submitted_at:'2026-10-16T00:00:00Z',profile:{},memories:[],voice_status:'none'}])
 render(<GuardianPortal/>);expect(await screen.findByText(label)).toBeVisible()
 expect(screen.getByRole('button',{name:'자료 다시 보내기'})).toBeVisible()
})
it('다른 환자의 전송 시트로 이전 동의를 넘기지 않는다',async()=>{
 mocks.targets.mockResolvedValue([{patient_id:'one',encounter_id:'admission',patient_name:'김하늘',hospital_ref:'TEST-FAVILIUM',relationship:'딸'},{patient_id:'two',encounter_id:'other',patient_name:'이온유',hospital_ref:'TEST-FAVILIUM',relationship:'아들'}])
 render(<GuardianPortal/>);const buttons=await screen.findAllByRole('button',{name:'자료 보내기'})
 fireEvent.click(buttons[0]);await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled());fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'가족 자료 보내기 닫기'}))
 fireEvent.click(buttons[1]);await waitFor(()=>expect(screen.getByRole('checkbox')).toBeEnabled());expect(screen.getByRole('checkbox')).not.toBeChecked()
 expect(screen.getByText('받는 대상 · 이온유')).toBeVisible()
})
