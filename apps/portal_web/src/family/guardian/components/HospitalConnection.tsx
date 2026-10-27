import { profileReady } from '../../studio/readiness'
import { useEffect, useRef, useState } from 'react'
import { RequestEpoch } from '../../../shared/hooks/requestEpoch'
import { HelpTooltip } from '../../../shared/components/HelpTooltip'
import { Panel } from '../../../shared/components/Panel'
import { ResponsiveSheet } from '../../../shared/components/ResponsiveSheet'
import { MATERIAL_LABELS, VOICE_LABELS, type FamilyMaterial, type MaterialTarget } from '../../../shared/api/familyMaterials'
import { studioRequest, type StudioState } from '../../studio/api'
import { categories } from '../../studio/MemoryLibrary'

type Props = {target:MaterialTarget;materials:FamilyMaterial[];busy:boolean;error:string;send:(target:MaterialTarget)=>Promise<boolean>;withdraw:(id:string)=>Promise<boolean>}
const submittedAt=(date:string)=>new Date(date).toLocaleString('ko-KR',{timeZone:'Asia/Seoul',month:'long',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:false})

export function HospitalConnection({target,materials,busy,error,send,withdraw}:Props) {
 const requests=useRef(new RequestEpoch())
 useEffect(()=>()=>requests.current.invalidate(),[])
 const [sheet,setSheet]=useState<'send'|FamilyMaterial|null>(null),[consent,setConsent]=useState(false),[withdrawing,setWithdrawing]=useState(false)
 const [preview,setPreview]=useState<StudioState|null>(null),[previewError,setPreviewError]=useState(''),[previewLoading,setPreviewLoading]=useState(false)
 const latest=materials[0],history=materials.slice(1)
 function close(){if(busy)return;requests.current.invalidate();setSheet(null);setConsent(false);setWithdrawing(false);setPreview(null);setPreviewError('')}
 async function prepare(){const owner=requests.current.begin();setSheet('send');setConsent(false);setPreview(null);setPreviewError('');setPreviewLoading(true)
  try{const state=await studioRequest<StudioState>('/state');if(requests.current.owns(owner))setPreview(state)}catch{if(requests.current.owns(owner))setPreviewError('보낼 자료를 확인하지 못했습니다. 닫은 뒤 다시 시도해주세요.')}finally{if(requests.current.owns(owner))setPreviewLoading(false)}
 }
 async function submit(){if(!consent||!preview)return;if(await send(target))close()}
 async function revoke(material:FamilyMaterial){if(await withdraw(material.material_id))close()}
 function materialSummary(material:FamilyMaterial){return <><div className="connection-result-heading"><strong>버전 {material.revision}</strong><span className="connection-status">{MATERIAL_LABELS[material.status]}</span></div><p className="connection-meta">기억 {material.memories.length}개 · {submittedAt(material.submitted_at)}</p>{material.review_note&&<div className="connection-review"><span>병원 검토 의견</span><p>{material.review_note}</p></div>}</>}
 const ready=Boolean(preview&&profileReady(preview.profile)&&preview.memories.length)
 return <Panel title={target.patient_name} className="hospital-connection" actions={<span className="connection-status">가족 연결 확인됨</span>}>
 <p className="connection-relationship">보호자 관계 · {target.relationship}</p>
 <details className="connection-identity"><summary>연결 정보</summary><p>병원 식별 코드 · {target.hospital_ref}</p></details>
 <div className="connection-current"><h3>최근 제출</h3>{latest?<>{materialSummary(latest)}{latest.status==='approved'&&<p className="connection-meta">환자 재생 · 별도 확인 필요</p>}</>:<p className="connection-meta">아직 보낸 자료가 없습니다.</p>}</div>
 <div className="connection-actions">{latest&&<button onClick={()=>{setSheet(latest);setWithdrawing(false)}}>보낸 자료 보기</button>}<button className="primary" disabled={busy||Boolean(error)} onClick={()=>void prepare()}>{latest?'자료 다시 보내기':'자료 보내기'}</button></div>
 {history.length>0&&<details className="connection-history"><summary>이전 제출 내역 {history.length}건</summary><ul>{history.map(material=><li key={material.material_id}>{materialSummary(material)}<button onClick={()=>{setSheet(material);setWithdrawing(false)}}>버전 {material.revision} 자료 보기</button></li>)}</ul></details>}
 <ResponsiveSheet open={sheet!==null} title={sheet==='send'?'가족 자료 보내기':'보낸 자료'} onClose={close}>
 {sheet==='send'?<div className="form-stack"><div className="connection-recipient"><div className="heading-with-help"><strong>받는 대상 · {target.patient_name}</strong><HelpTooltip label="자료 보내기 도움말">현재 저장한 소개·기억·음성 상태의 사본을 보냅니다. 제출 후 원본을 수정해도 보낸 내용은 바뀌지 않으며, 바뀐 자료는 다시 보내야 합니다.</HelpTooltip></div><span>보호자 관계 · {target.relationship}</span><span>병원 식별 코드 · {target.hospital_ref}</span></div>
 {previewLoading?<p role="status">보낼 자료 확인 중…</p>:previewError?<p role="alert">{previewError}</p>:preview&&<><dl className="connection-preview"><div><dt>가족 소개</dt><dd>{preview.profile.guardian_name||'입력 필요'} · {preview.profile.relationship||'관계 입력 필요'}</dd></div><div><dt>가족의 기억</dt><dd>{preview.memories.length}개</dd></div><div><dt>음성 등록 상태</dt><dd>{VOICE_LABELS[preview.voice.status]}</dd></div></dl><details className="connection-preview-details"><summary>보낼 내용 확인</summary><p>{preview.profile.patient_alias} · 호칭 {preview.profile.address_as}</p>{preview.memories.map(memory=><div key={memory.id}><strong>{categories[memory.category]} · {memory.title}</strong><p>{memory.content}</p></div>)}</details>{!ready&&<p role="status">가족 소개와 기억을 먼저 저장해주세요.</p>}</>}
 {error&&<p role="alert">{error} 닫은 뒤 다시 조회해주세요.</p>}<form className="form-stack connection-send-form" onSubmit={event=>{event.preventDefault();void submit()}}><label className="check-field"><input type="checkbox" checked={consent} disabled={busy||!ready} onChange={e=>setConsent(e.target.checked)}/><span>{target.patient_name}님의 담당 병원에 가족 소개·기억·음성 등록 상태를 보내는 데 동의합니다.</span></label><button className="primary" disabled={busy||Boolean(error)||!ready||!consent}>동의하고 보내기</button></form></div>:sheet&&<div className="form-stack"><div className="connection-recipient"><strong>{target.patient_name} · 버전 {sheet.revision}</strong><span>{MATERIAL_LABELS[sheet.status]} · {submittedAt(sheet.submitted_at)}</span></div>
 {sheet.review_note&&<div className="connection-review"><span>병원 검토 의견</span><p>{sheet.review_note}</p></div>}
 <section><h3>가족 소개</h3><dl className="connection-preview"><div><dt>보호자</dt><dd>{sheet.profile.guardian_name}</dd></div><div><dt>가족</dt><dd>{sheet.profile.patient_alias}</dd></div><div><dt>관계·호칭</dt><dd>{sheet.profile.relationship} · {sheet.profile.address_as}</dd></div></dl></section>
 <section><h3>가족의 기억 {sheet.memories.length}개</h3><ul className="connection-memory-list">{sheet.memories.map(memory=><li key={memory.id}><span className="connection-meta">{categories[memory.category]}</span><strong>{memory.title}</strong><p>{memory.content}</p></li>)}</ul></section>
 <section><div className="heading-with-help"><h3>보호자 제출 음성 상태</h3><HelpTooltip label="제출 음성 상태 도움말">보호자 제출값이며 공급자 등록·현재 사용 가능 여부를 병원에서 검증한 상태가 아닙니다.</HelpTooltip></div><p>{VOICE_LABELS[sheet.voice_status]} · 등록 여부 미검증</p></section>
 {['pending','approved'].includes(sheet.status)&&<div className="connection-withdraw">{error&&<p role="alert">{error} 닫은 뒤 다시 조회해주세요.</p>}{withdrawing?<><p>{target.patient_name}님의 버전 {sheet.revision} 공유를 철회할까요?</p><p className="connection-meta">이 자료는 음성 계획에 새로 연결할 수 없게 됩니다. 이미 남은 검토 기록은 유지됩니다.</p><div className="button-row"><button disabled={busy} onClick={()=>setWithdrawing(false)}>유지하기</button><button className="danger" disabled={busy||Boolean(error)} onClick={()=>void revoke(sheet)}>이 버전 공유 철회</button></div></>:<button disabled={busy} onClick={()=>setWithdrawing(true)}>공유 철회</button>}</div>}
 </div>}
 </ResponsiveSheet>
 </Panel>
}
