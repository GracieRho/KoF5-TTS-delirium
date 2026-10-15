import { HelpTooltip } from '../../../shared/components/HelpTooltip'
import { useEffect, useState } from 'react'
import { useAuth } from '../../../shared/auth/AuthContext'
import { Panel } from '../../../shared/components/Panel'
import { materialApi, MATERIAL_LABELS, type FamilyMaterial, type MaterialTarget } from '../../../shared/api/familyMaterials'
import { studioRequest } from '../../studio/api'

export function GuardianPortal() {
 const {api,token}=useAuth()
 const [targets,setTargets]=useState<MaterialTarget[]>([]),[materials,setMaterials]=useState<FamilyMaterial[]>([])
 const [loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[consent,setConsent]=useState(false)
 async function reload(){if(!api||!token)return;setLoading(true);setError('');try{const [t,m]=await Promise.all([materialApi.targets(api,token),materialApi.list(api,token)]);setTargets(t);setMaterials(m)}catch{setError('병원 연결과 제출 자료를 확인하지 못했습니다.')}finally{setLoading(false)}}
 useEffect(()=>{void reload()},[api,token])
 async function share(target:MaterialTarget){setBusy(true);setError('');try{const result=await studioRequest<{material_id:string}>('/hospital-materials','POST',{patient_id:target.patient_id,encounter_id:target.encounter_id,sharing_consent:consent});await reload();if(!result.material_id)throw new Error('자료 전송을 확인하지 못했습니다.')}catch(e){setError(e instanceof Error?e.message:'자료 전송 결과를 확인하지 못했습니다.')}finally{setBusy(false)}}
 async function withdraw(id:string){if(!api||!token)return;setBusy(true);setError('');try{await materialApi.withdraw(api,token,id);await reload()}catch{setError('공유 철회 결과를 확인하지 못했습니다. 다시 조회해주세요.')}finally{setBusy(false)}}
 return <section className="stack"><div className="section-heading"><div className="heading-with-help"><h1>병원 연결</h1><HelpTooltip label="병원 연결 도움말">소개는 시작 화면에서, 기억은 가족의 기억에서 수정합니다. 자료 보내기는 현재 저장한 소개·기억·음성 등록 상태의 사본을 병원 검토에 제출합니다. 수정 후에는 다시 보내야 합니다.</HelpTooltip></div><button disabled={busy||loading} onClick={()=>void reload()}>다시 조회</button></div>
 {error&&<p role="alert" className="blocking-note">{error}</p>}
 {loading?<p role="status">병원 연결 확인 중…</p>:!error&&(!targets.length?<Panel title="연결된 병원"><p>확인된 입원 연결이 없습니다. 병원 담당자에게 가족 연결을 요청해주세요.</p></Panel>:<>
 <label className="check-row"><input type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/>저장한 가족 소개·기억·음성 등록 상태를 담당 병원에 보내는 데 동의합니다.</label>
 {targets.map(target=><Panel key={target.encounter_id} title={target.patient_name}><p>{target.hospital_ref} · {target.relationship} · 가족 연결 확인됨</p><button className="primary" disabled={busy||!consent} onClick={()=>void share(target)}>현재 자료 보내기</button>
 <ul className="item-list">{materials.filter(m=>m.patient_id===target.patient_id&&m.encounter_id===target.encounter_id).map(m=><li className="item" key={m.material_id}><strong>버전 {m.revision} · {MATERIAL_LABELS[m.status]}</strong><p>{m.memories.length}개 기억 · {new Date(m.submitted_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'})}</p>{m.review_note&&<p>병원 검토 의견 · {m.review_note}</p>}<details><summary>보낸 자료 확인</summary>{m.memories.map(memory=><div key={memory.id}><strong>{memory.title}</strong><p>{memory.content}</p></div>)}<small>자료 ID {m.material_id}</small></details>{['pending','approved'].includes(m.status)&&<button disabled={busy} onClick={()=>void withdraw(m.material_id)}>공유 철회</button>}</li>)}</ul>
 {!materials.some(m=>m.encounter_id===target.encounter_id)&&<p className="empty-state">아직 보낸 자료가 없습니다.</p>}</Panel>)}
 </>)}
 </section>
}
