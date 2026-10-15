import { HelpTooltip } from '../../../shared/components/HelpTooltip'
import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../../../shared/auth/AuthContext'
import { Panel } from '../../../shared/components/Panel'
import { materialApi, type FamilyMaterial, type MaterialTarget } from '../../../shared/api/familyMaterials'
import { RequestEpoch } from '../../../shared/hooks/requestEpoch'
import { studioRequest } from '../../studio/api'
import { HospitalConnection } from '../components/HospitalConnection'
import '../styles/connections.css'

export function GuardianPortal() {
 const {api,token}=useAuth(),requests=useRef(new RequestEpoch())
 const [targets,setTargets]=useState<MaterialTarget[]>([]),[materials,setMaterials]=useState<FamilyMaterial[]>([])
 const [loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState('')
 async function reload(){if(!api||!token)return false;const owner=requests.current.begin();setLoading(true);setError('');try{const [t,m]=await Promise.all([materialApi.targets(api,token),materialApi.list(api,token)]);if(!requests.current.owns(owner))return false;setTargets(t);setMaterials(m);return true}catch{if(requests.current.owns(owner))setError('병원 연결과 제출 자료를 확인하지 못했습니다.');return false}finally{if(requests.current.owns(owner))setLoading(false)}}
 useEffect(()=>{setTargets([]);setMaterials([]);void reload();return()=>requests.current.invalidate()},[api,token])
 async function share(target:MaterialTarget){setBusy(true);setError('');try{const result=await studioRequest<{material_id:string}>('/hospital-materials','POST',{patient_id:target.patient_id,encounter_id:target.encounter_id,sharing_consent:true});if(!result.material_id)throw new Error('자료 전송을 확인하지 못했습니다.');return await reload()}catch(e){setError(e instanceof Error?e.message:'자료 전송 결과를 확인하지 못했습니다.');return false}finally{setBusy(false)}}
 async function withdraw(id:string){if(!api||!token)return false;setBusy(true);setError('');try{await materialApi.withdraw(api,token,id);return await reload()}catch{setError('공유 철회 결과를 확인하지 못했습니다. 다시 조회해주세요.');return false}finally{setBusy(false)}}
 return <section className="guardian-connections"><div className="section-heading"><div className="heading-with-help"><h1>병원 연결</h1><HelpTooltip label="병원 연결 도움말">소개는 시작 화면에서, 기억은 가족의 기억에서 수정합니다. 보낸 자료는 제출 당시의 사본이며 수정 후에는 다시 보내야 합니다. 병원 검토 완료와 환자 재생 준비는 별도 상태입니다.</HelpTooltip></div><button disabled={busy||loading} onClick={()=>void reload()}>새로고침</button></div>
 {error&&<div role="alert" className="blocking-note"><p>{error}</p><button disabled={busy||loading} onClick={()=>void reload()}>다시 시도</button></div>}
 {loading&&!targets.length?<p role="status">병원 연결 확인 중…</p>:!targets.length&&!error?<Panel title="연결된 병원"><p>확인된 입원 연결이 없습니다. 병원 담당자에게 가족 연결을 요청해주세요.</p></Panel>:targets.map(target=><HospitalConnection key={target.encounter_id} target={target} materials={materials.filter(m=>m.patient_id===target.patient_id&&m.encounter_id===target.encounter_id).sort((a,b)=>b.revision-a.revision)} busy={busy||loading} error={error} send={share} withdraw={withdraw}/>)}
 </section>
}
