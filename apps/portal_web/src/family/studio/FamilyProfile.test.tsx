import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { FamilyProfile } from './FamilyProfile'

it('기존 가족 소개를 보존하며 반존대와 여러 호칭을 저장한다', async () => {
  const save = vi.fn().mockResolvedValue(undefined)
  render(<FamilyProfile profile={{ guardian_name: '가상 보호자', patient_alias: '가상 가족', relationship: '딸', address_as: '아빠' }} busy={false} onSave={save} />)
  fireEvent.change(screen.getByLabelText('다른 호칭들 (쉼표로 구분)'), { target: { value: '아버지, 우리 아빠, 아버지' } })
  fireEvent.click(screen.getByRole('combobox', { name: '평소 말투' }))
  fireEvent.click(screen.getByRole('option', { name: '반존대' }))
  fireEvent.click(screen.getByRole('button', { name: '가족 소개 저장' }))
  await waitFor(() => expect(save).toHaveBeenCalledWith({
    guardian_name: '가상 보호자', patient_alias: '가상 가족', relationship: '딸', address_as: '아빠',
    address_aliases: ['아버지', '우리 아빠'], speech_style: 'mixed'
  }))
})
