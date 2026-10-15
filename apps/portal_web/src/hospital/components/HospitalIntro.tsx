import { Icon } from '../../shared/components/Icon'

export function HospitalIntro() {
  return (
    <section className="hospital-intro" aria-labelledby="hospital-intro-title">
      <div>
        <h1 id="hospital-intro-title">
          환자 곁의 돌봄,
          <br />
          한곳에서 이어지도록.
        </h1>
        <p>
          가족의 기억과 병원의 정보를 구분하고,
          <br />
          확인된 내용을 익숙한 목소리로 전할 수 있도록 준비합니다.
        </p>
      </div>
      <ul className="hospital-workflow" aria-label="병원 업무 흐름">
        <li>
          <Icon name="patient" size={20} />
          <div>
            <strong>담당 환자</strong>
            <span>현재 입원과 연결 확인</span>
          </div>
        </li>
        <li>
          <Icon name="shield" size={20} />
          <div>
            <strong>승인 정보</strong>
            <span>병실·검사·일정 검토</span>
          </div>
        </li>
        <li>
          <Icon name="chat" size={20} />
          <div>
            <strong>전달 관리</strong>
            <span>메시지와 전달 상태 확인</span>
          </div>
        </li>
      </ul>
    </section>
  )
}
