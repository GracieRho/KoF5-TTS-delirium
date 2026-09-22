import { describe, expect, it } from 'vitest'
import { shouldClearSession } from './sessionGuard'

describe('세션 오류 소유권', () => {
  it('이전 요청의 인증 오류로 새 세션을 지우지 않는다', () => {
    expect(shouldClearSession('new-token', 'old-token')).toBe(false)
    expect(shouldClearSession('new-token', 'new-token')).toBe(true)
  })
})
