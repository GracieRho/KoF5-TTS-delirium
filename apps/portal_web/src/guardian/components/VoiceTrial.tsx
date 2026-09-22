import { StatusMessage } from '../../shared/components/StatusMessage'
import { useGuardianVoiceTrial } from '../hooks/useGuardianVoiceTrial'

export function VoiceTrial({ patientId, token }: { patientId: string; token: string }) {
  const voice = useGuardianVoiceTrial(patientId, token, true)
  return <div><p className="compact">고정 합성 환자 자료와 테스터 본인의 목소리만 사용합니다. 실제 환자·보호자 음성은 녹음하지 마세요.</p><ol>{voice.samples.map((sample, index) => <li key={index}>{index + 1}번째 샘플 · {(sample.durationMs / 1000).toFixed(1)}초 · 로컬 참조만 유지</li>)}</ol><div className="button-row"><button disabled={!voice.ready || voice.busy || voice.recording || voice.samples.length >= 3} onClick={() => void voice.start()}>다음 합성 샘플 녹음</button><button disabled={!voice.recording} onClick={() => voice.stop()}>녹음 끝내기</button><button disabled={voice.busy || voice.recording || voice.samples.length !== 3} onClick={() => void voice.enroll()}>세 샘플 합성 업로드</button><button className="danger" disabled={voice.busy || !voice.remote?.clone_id} onClick={() => void voice.mutate('delete')}>합성 복제 삭제 요청</button><button disabled={voice.busy || voice.remote?.status !== 'pending'} onClick={() => void voice.mutate('reconcile')}>원격 상태 대조</button><button disabled={voice.busy || voice.recording} onClick={() => void voice.refresh()}>상태 다시 확인</button></div><StatusMessage>{voice.status}</StatusMessage></div>
}
