import type { SupabaseRest } from './supabase'
import type { Memory, Profile, StudioState } from '../../family/studio/api'
export type MaterialTarget={patient_id:string;encounter_id:string;patient_name:string;hospital_ref:string;relationship:string}
export type FamilyMaterial={material_id:string;patient_id:string;encounter_id:string;revision:number;content_hash:string;profile:Profile;memories:Memory[];voice_status:StudioState['voice']['status'];voice_revision:string;status:'pending'|'approved'|'rejected'|'withdrawn'|'superseded';submitted_at:string;review_note:string;reviewed_at:string|null}
export const MATERIAL_LABELS:Record<FamilyMaterial['status'],string>={pending:'검토 대기',approved:'검토 완료',rejected:'보완 요청',withdrawn:'공유 철회',superseded:'이전 버전'}
export const VOICE_LABELS:Record<StudioState['voice']['status'],string>={none:'미등록',failed:'등록 실패',pending:'등록 확인 중',verification_pending:'본인 확인 대기',created:'등록됨',deletion_pending:'삭제 확인 중',deleted:'삭제됨'}
export const materialApi={
 targets:(api:SupabaseRest,token:string)=>api.request<MaterialTarget[]>('/rest/v1/rpc/guardian_material_targets',{method:'POST',schema:'api',token,body:{}}),
 list:(api:SupabaseRest,token:string,patient?:string,encounter?:string)=>api.request<FamilyMaterial[]>(`/rest/v1/family_material?select=*&order=submitted_at.desc${patient?'&patient_id=eq.'+encodeURIComponent(patient):''}${encounter?'&encounter_id=eq.'+encodeURIComponent(encounter):''}`,{schema:'api',token}),
 bindings:(api:SupabaseRest,token:string)=>api.request<{schedule_id:string;material_id:string}[]>('/rest/v1/family_material_plan?select=schedule_id,material_id',{schema:'api',token}),
 review:(api:SupabaseRest,token:string,id:string,decision:'approved'|'rejected',note:string)=>api.request('/rest/v1/rpc/review_family_material',{method:'POST',schema:'api',token,body:{_id:id,_decision:decision,_note:note}}),
 withdraw:(api:SupabaseRest,token:string,id:string)=>api.request('/rest/v1/rpc/withdraw_family_material',{method:'POST',schema:'api',token,body:{_id:id}}),
 link:(api:SupabaseRest,token:string,id:string,schedule:string)=>api.request('/rest/v1/rpc/link_family_material_plan',{method:'POST',schema:'api',token,body:{_id:id,_schedule:schedule}})
}
