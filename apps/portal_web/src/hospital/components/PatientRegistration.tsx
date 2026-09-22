import { useState, type FormEvent } from 'react'
import type { SupabaseRest } from '../../shared/api/supabase'
import type { HospitalReadiness } from '../../shared/types/domain'
import { StatusMessage } from '../../shared/components/StatusMessage'
import { hospitalApi } from '../api/hospitalApi'

export function PatientRegistration({ api, token, readiness, onDone }: { api: SupabaseRest; token: string; readiness: HospitalReadiness[]; onDone: () => Promise<void> }) {
  const hospitals = readiness.filter(row => row.ready); const [hospital, setHospital] = useState(''); const [patientRef, setPatientRef] = useState(''); const [name, setName] = useState(''); const [birth, setBirth] = useState(''); const [status, setStatus] = useState(''); const [busy, setBusy] = useState(false)
  async function submit(event: FormEvent) { event.preventDefault(); if (!hospital || !patientRef.trim() || !name.trim()) return; setBusy(true); try { await hospitalApi.register(api, token, { hospital_ref: hospital, ehr_patient_ref: patientRef.trim(), staff_display_name: name.trim(), ...(birth ? { birth_date: birth } : {}) }); setPatientRef(''); setName(''); setBirth(''); await onDone(); setStatus('환자 기본정보를 등록하고 목록을 갱신했습니다.') } catch { setStatus('등록하지 못했습니다. 중복 번호, 권한, 기관 승인을 확인하세요.') } finally { setBusy(false) } }
  if (!hospitals.length) return <StatusMessage tone="warning">현재 환자 등록 승인이 준비된 병원이 없습니다.</StatusMessage>
  return <form className="form-stack" onSubmit={submit}><label>병원<select required value={hospital} onChange={e => setHospital(e.target.value)}><option value="">병원 선택</option>{hospitals.map(row => <option key={row.hospital_ref}>{row.hospital_ref}</option>)}</select></label><label>병원 환자 번호<input required maxLength={100} value={patientRef} onChange={e => setPatientRef(e.target.value)}/></label><label>환자 성명<input required maxLength={100} value={name} onChange={e => setName(e.target.value)}/></label><label>생년월일 (선택)<input type="date" value={birth} onChange={e => setBirth(e.target.value)}/></label><button className="primary" disabled={busy}>{busy ? '등록 중' : '환자 등록'}</button><StatusMessage>{status}</StatusMessage></form>
}
