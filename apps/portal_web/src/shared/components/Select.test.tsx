import { act, fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { Select } from './Select'

const rows = [<option value="">전체</option>,<option value="one">햇살병동</option>,<option disabled value="two">이용 불가</option>,<option value="three">새봄병동</option>]
it('키보드 이동은 비활성 항목을 건너뛰고 Enter에서만 선택한다', () => {
  const change = vi.fn()
  render(<Select label="병동" value="one" onValueChange={change}>{rows}</Select>)
  const trigger = screen.getByRole('combobox', { name:'병동' })
  fireEvent.keyDown(trigger, {key:'ArrowDown'})
  fireEvent.keyDown(trigger, {key:'ArrowDown'})
  expect(change).not.toHaveBeenCalled()
  fireEvent.keyDown(trigger, {key:'Enter'})
  expect(change).toHaveBeenCalledWith('three')
  expect(trigger).toHaveAttribute('aria-expanded','false')
})
it('Escape와 바깥 클릭은 선택값을 바꾸지 않는다', () => {
  const change = vi.fn()
  render(<Select label="병동" value="one" onValueChange={change}>{rows}</Select>)
  const trigger = screen.getByRole('combobox', { name:'병동' })
  fireEvent.click(trigger); fireEvent.keyDown(trigger,{key:'End'}); fireEvent.keyDown(trigger,{key:'Escape'})
  expect(trigger).toHaveAttribute('aria-expanded','false')
  fireEvent.click(trigger); fireEvent.pointerDown(document.body)
  expect(trigger).toHaveAttribute('aria-expanded','false'); expect(change).not.toHaveBeenCalled()
})
it('선택값은 실제 폼 값으로 남고 필수 선택 검사를 유지한다', () => {
  const {container} = render(<form><Select name="ward" label="병동" required onValueChange={()=>{}}>{rows}</Select></form>)
  const form = container.querySelector('form')!
  act(() => { expect(form.checkValidity()).toBe(false) })
  const trigger = screen.getByRole('combobox', {name:'병동'})
  expect(trigger).toHaveAttribute('aria-invalid','true')
  fireEvent.click(screen.getByRole('option',{name:'햇살병동'}))
  expect(form.checkValidity()).toBe(true)
  expect(new FormData(form).get('ward')).toBe('one')
})
it('입력한 글자로 항목을 찾고 비활성 메뉴는 열리지 않는다', () => {
  const change=vi.fn(), {rerender}=render(<Select label="병동" value="" onValueChange={change}>{rows}</Select>)
  const trigger=screen.getByRole('combobox',{name:'병동'})
  fireEvent.keyDown(trigger,{key:'새'})
  expect(change).toHaveBeenCalledWith('three')
  rerender(<Select label="병동" disabled value="" onValueChange={change}>{rows}</Select>)
  fireEvent.click(trigger);expect(trigger).toHaveAttribute('aria-expanded','false')
})
