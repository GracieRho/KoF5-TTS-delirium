export const SYNTHETIC_PATIENT_ID = '00000000-0000-4000-8000-000000000975'
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const FAMILY_LABELS: Record<string, string> = {
  family: '가족', relationship: '가족과 관계', hometown: '고향', occupation: '예전 일', food: '좋아하는 음식',
  hobby: '취미', friend: '친구', pet: '반려동물', daily_routine: '평소 일과', travel: '함께한 여행',
  family_event: '가족 행사', favorite_story: '좋아하는 이야기', recent_event: '최근 일', comfort_topic: '안심되는 이야기', avoid_topic: '피해야 할 이야기',
}
export const CONTEXT_LABELS: Record<string, string> = { hospital: '병원', ward: '병동', room: '병실', test_schedule: '검사 일정', visit_schedule: '면회 일정', test: '검사', visiting: '면회', schedule: '일정' }
