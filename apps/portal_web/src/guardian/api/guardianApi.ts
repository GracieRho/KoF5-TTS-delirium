import type { SupabaseRest } from '../../shared/api/supabase'
import type { FamilyFact, GuardianLink } from '../../shared/types/domain'

export const guardianApi = {
  links: (api: SupabaseRest, token: string) => api.request<GuardianLink[]>('/rest/v1/guardian_links?select=patient_id,relationship,access_status,effective_at,expires_at', { token, schema: 'api' }),
  facts: (api: SupabaseRest, token: string, patientId: string) => api.request<FamilyFact[]>(`/rest/v1/family_context?patient_id=eq.${encodeURIComponent(patientId)}&select=fact_id,category,content&order=created_at.desc`, { token, schema: 'api' }),
  createFact: (api: SupabaseRest, token: string, patientId: string, category: string, content: string) => api.request<FamilyFact[]>('/rest/v1/family_context', { method: 'POST', token, schema: 'api', returnRow: true, body: { patient_id: patientId, category, content } }),
  updateFact: (api: SupabaseRest, token: string, patientId: string, factId: string, category: string, content: string) => api.request<FamilyFact[]>(`/rest/v1/family_context?fact_id=eq.${encodeURIComponent(factId)}&patient_id=eq.${encodeURIComponent(patientId)}`, { method: 'PATCH', token, schema: 'api', returnRow: true, body: { category, content } }),
}

export function validLink(link: GuardianLink, now = Date.now()) { return link.access_status === 'verified' && Date.parse(link.effective_at) <= now && (!link.expires_at || Date.parse(link.expires_at) > now) }
