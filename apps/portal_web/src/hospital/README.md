# 병원 직원 화면

- `pages/HospitalPortal.tsx`: `/hospital` 진입점, 로그인 및 담당 환자 업무.
- `components/`, `hooks/`, `api/`: 현재 입원·승인 정보·메시지·기기 업무와 기존 직원 권한 경계.
- `styles/hospital.css`: 인디고·블루·시안·민트 테마. `.hospital-theme` 안에 한정해 가족 화면에 영향을 주지 않는다.
- `assets/`: 같은 Favilium 심볼의 병원 색상 변형.
- 가족 음성/기억 설정은 `../family/`, 공용 셸·인증·폼은 `../shared/`에서 관리한다.

전체 규격은 루트 `DESIGN.md`를 따른다. 원격 프로젝트·기관 계정 연결은 별도 설정이 필요하며 화면 표시만으로 연결 또는 임상 승인을 뜻하지 않는다.
