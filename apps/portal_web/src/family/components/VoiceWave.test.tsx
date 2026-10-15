import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it } from 'vitest'
import { VoiceWave } from './VoiceWave'

it('장식 파형을 멈추고 다시 재생할 수 있다', () => {
  render(<VoiceWave />)
  fireEvent.click(screen.getByRole('button', { name: '파형 움직임 멈추기' }))
  expect(screen.getByRole('button', { name: '파형 움직임 재생' })).toHaveAttribute(
    'aria-pressed',
    'true'
  )
  fireEvent.click(screen.getByRole('button', { name: '파형 움직임 재생' }))
  expect(screen.getByRole('button', { name: '파형 움직임 멈추기' })).toHaveAttribute(
    'aria-pressed',
    'false'
  )
})
