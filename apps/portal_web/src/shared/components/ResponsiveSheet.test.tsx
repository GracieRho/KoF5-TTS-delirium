import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { ResponsiveSheet } from './ResponsiveSheet'

HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', '') }
HTMLDialogElement.prototype.close = function () { this.removeAttribute('open') }

it('편집 작업을 모달 시트로 열고 닫는다', () => {
  const close = vi.fn()
  render(<ResponsiveSheet open title="기억 수정" onClose={close}><p>편집 폼</p></ResponsiveSheet>)
  expect(screen.getByRole('dialog')).toHaveAttribute('open')
  fireEvent.click(screen.getByRole('button', { name: '기억 수정 닫기' }))
  expect(close).toHaveBeenCalledOnce()
})
