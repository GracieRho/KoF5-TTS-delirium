import { useState } from 'react'
import '../styles/motion.css'

export function VoiceWave() {
  const [paused, setPaused] = useState(false)
  return (
    <div className="voice-wave" data-paused={paused}>
      <div className="welcome-art" aria-hidden="true">
        <span />
        <span />
        <span />
        <span />
        <span />
        <span />
        <span />
      </div>
      <button
        className="wave-motion-toggle"
        type="button"
        aria-label={paused ? '파형 움직임 재생' : '파형 움직임 멈추기'}
        aria-pressed={paused}
        onClick={() => setPaused(!paused)}
      >
        <span aria-hidden="true">{paused ? '▶' : 'Ⅱ'}</span>
      </button>
    </div>
  )
}
