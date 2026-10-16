import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it } from 'vitest'
import { HelpTooltip } from './HelpTooltip'
it('설명은 기본적으로 숨기고 호버·포커스에서 표시한다', () => {
 render(<HelpTooltip label="조회 범위 도움말">권한이 있는 기록 기준입니다.</HelpTooltip>)
 expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
 const trigger=screen.getByRole('button',{name:'조회 범위 도움말'})
 fireEvent.mouseEnter(trigger.parentElement!)
 expect(screen.getByRole('tooltip')).toHaveTextContent('권한이 있는 기록 기준입니다.')
 fireEvent.mouseLeave(trigger.parentElement!)
 expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
 fireEvent.focus(trigger);fireEvent.mouseLeave(trigger.parentElement!);expect(screen.getByRole('tooltip')).toBeInTheDocument()
 fireEvent.keyDown(trigger,{key:'Escape'});expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
})
it('클릭으로 고정하고 다시 클릭하거나 바깥을 누르면 닫힌다', () => {
 render(<HelpTooltip>설명</HelpTooltip>)
 const trigger=screen.getByRole('button',{name:'도움말'})
 fireEvent.click(trigger);fireEvent.mouseLeave(trigger.parentElement!)
 expect(screen.getByRole('tooltip')).toBeInTheDocument()
 fireEvent.click(trigger);expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
 fireEvent.click(trigger);fireEvent.pointerDown(document.body)
 expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
})
