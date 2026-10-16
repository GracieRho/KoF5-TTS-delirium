import { Select } from '../../shared/components/Select'
import { useState, type FormEvent } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import type { HospitalReadiness } from '../../shared/types/domain'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'

export function PatientRegistration({ api, token, readiness, onDone }: { api: SupabaseRest; token: string; readiness: HospitalReadiness[]; onDone: () => Promise<void> }) {
 const hospitals=readiness.filter(row=>row.ready)
 const [hospital,setHospital]=useState(hospitals.length===1?hospitals[0].hospital_ref:''),[patientRef,setPatientRef]=useState(''),[name,setName]=useState(''),[ward,setWard]=useState(''),[room,setRoom]=useState(''),[bed,setBed]=useState(''),[status,setStatus]=useState(''),[busy,setBusy]=useState(false)
 async function submit(event:FormEvent) {event.preventDefault();if(busy)return;setBusy(true)
  try {await hospitalApi.rpc(api,token,'register_care_admission',{_hospital:hospital,_patient_ref:patientRef.trim(),_name:name.trim(),_ward:ward.trim(),_room:room.trim(),_bed:bed.trim()});await onDone();setStatus('환자와 현재 입원을 등록했습니다.')}
  catch {setStatus('등록하지 못했습니다. 중복 환자 번호, 담당 자격과 기관 승인을 확인해주세요.')}
  finally {setBusy(false)}
 }
 if(!hospitals.length)return <p className="blocking-note">현재 환자 등록 승인이 준비된 병원이 없습니다. 기관의 등록 승인을 먼저 확인해주세요.</p>
 return <form className="form-stack" onSubmit={e=>void submit(e)}><Select help="환자와 현재 입원을 함께 등록합니다. 기록 작성에는 별도의 돌봄 자격과 담당 배정이 필요합니다." label="병원" required value={hospital} onValueChange={selectedValue =>setHospital(selectedValue)}><option value="">병원 선택</option>{hospitals.map(row=><option key={row.hospital_ref}>{row.hospital_ref}</option>)}</Select><label>병원 환자 번호<input required maxLength={100} value={patientRef} onChange={e=>setPatientRef(e.target.value)}/></label><label>환자 성명<input required maxLength={100} value={name} onChange={e=>setName(e.target.value)}/></label><label>병동<input required maxLength={80} value={ward} onChange={e=>setWard(e.target.value)}/></label><label>병실<input required maxLength={80} value={room} onChange={e=>setRoom(e.target.value)}/></label><label>침상<input required maxLength={80} value={bed} onChange={e=>setBed(e.target.value)}/></label><button className="primary" disabled={busy}>{busy?'등록 중…':'환자·입원 등록'}</button><StatusMessage>{status}</StatusMessage></form>
}
