import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { StatusMessage, ToastProvider } from './StatusMessage'

describe('작업 피드백 토스트', () => {
  it('본문 박스 대신 한 개의 전역 토스트만 표시한다', async () => {
    const { rerender } = render(<ToastProvider><main data-testid="content"><StatusMessage>저장했습니다.</StatusMessage></main></ToastProvider>)
    expect(await screen.findByRole('status')).toHaveTextContent('저장했습니다.')
    expect(screen.getByTestId('content')).toBeEmptyDOMElement()

    rerender(<ToastProvider><StatusMessage tone="danger">저장하지 못했습니다.</StatusMessage></ToastProvider>)
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('저장하지 못했습니다.'))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })
})
