import type { SupabaseRest } from '../../shared/api/supabase'
import type { ContextDraft, HospitalFact, HospitalMessage, HospitalReadiness, MessageDraft, Patient, Transcript } from '../../shared/types/domain'

const select = {
  patients: '/rest/v1/hospital_patient_list?select=patient_id,ehr_patient_ref,staff_display_name,encounter_id,ward_ref,room_ref,bed_ref',
  readiness: '/rest/v1/hospital_registration_ready?select=hospital_ref,ready',
  queue: '/rest/v1/hospital_message_list?delivery_status=eq.pending&select=patient_id,encounter_id,approved_text,due_at,delivery_status&order=due_at.asc&limit=100',
}

export const hospitalApi = {
  patients: (api: SupabaseRest, token: string) => api.request<Patient[]>(select.patients, { token, schema: 'api' }),
  readiness: (api: SupabaseRest, token: string) => api.request<HospitalReadiness[]>(select.readiness, { token, schema: 'api' }),
  queue: (api: SupabaseRest, token: string) => api.request<HospitalMessage[]>(select.queue, { token, schema: 'api' }),
  facts: (api: SupabaseRest, token: string, patientId: string) => api.request<HospitalFact[]>(`/rest/v1/hospital_context_current?patient_id=eq.${encodeURIComponent(patientId)}&select=fact_id,category,content,encounter_id,verified_at,valid_until,synthetic_source_ref`, { token, schema: 'api' }),
  messages: (api: SupabaseRest, token: string, patientId: string) => api.request<HospitalMessage[]>(`/rest/v1/hospital_message_list?patient_id=eq.${encodeURIComponent(patientId)}&select=message_id,approved_text,approved_by_staff_ref,approved_at,due_at,delivery_status,delivered_at,cancelled_at,encounter_id`, { token, schema: 'api' }),
  transcripts: (api: SupabaseRest, token: string, patient: Patient) => api.request<Transcript[]>(`/rest/v1/synthetic_today_transcript?patient_id=eq.${patient.patient_id}&encounter_id=eq.${patient.encounter_id}&select=turn_id,transcript,captured_at&order=captured_at.desc&limit=100`, { token, schema: 'api' }),
  register: (api: SupabaseRest, token: string, body: unknown) => api.request<unknown>('/rest/v1/hospital_patient_registration', { method: 'POST', token, schema: 'api', body }),
  pair: (api: SupabaseRest, token: string, body: unknown) => api.request<unknown>('/rest/v1/patient_device_pairing', { method: 'POST', token, schema: 'api', body }),
  messageDrafts: (api: SupabaseRest, token: string, patient: Patient) => api.request<MessageDraft[]>(`/rest/v1/synthetic_hospital_message_draft?patient_id=eq.${patient.patient_id}&encounter_id=eq.${patient.encounter_id}&status=eq.draft&select=draft_id,proposed_text,schedule_mode,requested_due_at,proposed_by_auth_user_id,proposed_at,status&order=proposed_at.desc&limit=20`, { token, schema: 'api' }),
  createMessageDraft: (api: SupabaseRest, token: string, body: unknown) => api.request<unknown>('/rest/v1/synthetic_hospital_message_draft', { method: 'POST', token, schema: 'api', body }),
  approveMessageDraft: (api: SupabaseRest, token: string, id: string) => api.request<unknown>(`/rest/v1/synthetic_hospital_message_draft?draft_id=eq.${id}&status=eq.draft`, { method: 'PATCH', token, schema: 'api', body: { status: 'approved' }, returnRow: true }),
  approvedMessageDraft: (api: SupabaseRest, token: string, id: string) => api.request<Array<{ status: string; approved_by_auth_user_id: string; proposed_text: string }>>(`/rest/v1/synthetic_hospital_message_draft?draft_id=eq.${id}&select=status,approved_by_auth_user_id,proposed_text`, { token, schema: 'api' }),
  queuedMessage: (api: SupabaseRest, token: string, id: string) => api.request<Array<{ approved_text: string; delivery_status: string; encounter_id: string }>>(`/rest/v1/hospital_message_list?message_id=eq.${id}&select=approved_text,delivery_status,encounter_id`, { token, schema: 'api' }),
  contextDrafts: (api: SupabaseRest, token: string, patient: Patient) => api.request<ContextDraft[]>(`/rest/v1/synthetic_hospital_context_draft?patient_id=eq.${patient.patient_id}&encounter_id=eq.${patient.encounter_id}&status=eq.draft&select=draft_id,patient_id,encounter_id,category,proposed_text,source_ref,proposed_by_auth_user_id,proposed_at,status&order=proposed_at.desc&limit=20`, { token, schema: 'api' }),
  createContextDraft: (api: SupabaseRest, token: string, body: unknown) => api.request<unknown>('/rest/v1/synthetic_hospital_context_draft', { method: 'POST', token, schema: 'api', body }),
  approveContextDraft: (api: SupabaseRest, token: string, id: string) => api.request<unknown>(`/rest/v1/synthetic_hospital_context_draft?draft_id=eq.${id}&status=eq.draft`, { method: 'PATCH', token, schema: 'api', body: { status: 'approved' }, returnRow: true }),
  approvedContextDraft: (api: SupabaseRest, token: string, id: string) => api.request<Array<ContextDraft & { approved_by_auth_user_id: string }>>(`/rest/v1/synthetic_hospital_context_draft?draft_id=eq.${id}&select=draft_id,patient_id,encounter_id,category,proposed_text,source_ref,proposed_by_auth_user_id,status,approved_by_auth_user_id`, { token, schema: 'api' }),
  approvedContextFact: (api: SupabaseRest, token: string, id: string, patientId: string) => api.request<Array<{ fact_id: string; patient_id: string; encounter_id: string; category: string; content: string; synthetic_source_ref: string }>>(`/rest/v1/hospital_context_current?fact_id=eq.${id}&patient_id=eq.${patientId}&select=fact_id,patient_id,encounter_id,category,content,synthetic_source_ref`, { token, schema: 'api' }),
  rpc: <T>(api: SupabaseRest, token: string, name: string, body: unknown = {}) => api.request<T>(`/rest/v1/rpc/${name}`, { method: 'POST', token, schema: 'api', body }),
}
