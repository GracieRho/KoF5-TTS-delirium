# 보호자·병원 역할과 가상 자료

## 완료 범위

- 보호자 `guardian@email.com` / `test1234`, 병원 `hospital@email.com` / `test1234`. 실제 원격 계정이 아닌 이 프로젝트의 로컬 Supabase Auth 계정이다.
- 가상 환자 6명, 현재 입원·병동·병실, 병원 승인 사실 18건, 안내 메시지 12건(대기 7·가상 전달 이력 5), 가족 기억 6건. 실존 인물·임상 기록에서 가져오지 않았다.
- 첫 환자는 기기 시험 예약 ID `…975`와 분리한 `…976`. 기기·2인 승인·기관 승인 제한을 우회하지 않는다. 후속 병원 돌봄 확장에서 이 전용 로컬 기관에만 TEST 승인 근거와 만료일을 갖춘 등록·돌봄 권한을 설정했다. 원격 기관의 승인을 의미하지 않는다.
- 보호자 `/studio`와 병원 `/hospital`만 독립 공간이다. `/guardian`은 스튜디오 내부 병원 연결 탭으로 이동한다. 상대 역할의 메뉴·헤더 링크와 중복 병원 업무 메뉴를 제거했다.
- 서버 RPC는 유효한 Auth 세션과 보호자 연결/직원 승인 기록으로 역할을 계산한다. 모든 PostgREST 요청은 pre-request에서 세션 폐기를 확인하고 기존 RLS를 그대로 적용한다.
- `/local-studio/*`는 루프백·명시적 활성화·같은 Origin·보호자 JWT·지정 계정 소유권을 모두 요구한다. 현재 SQLite 공간은 보호자 한 계정 전용이며 저장된 소유자와 다른 계정으로 재지정하면 거부한다.
- 탭의 sessionStorage에 토큰만 보관하고 복원 시 서버에서 재검증한다. 자동 refresh는 구현하지 않아 만료 후 재로그인이 필요하다. 로그아웃은 현재 서버 세션을 폐기하며 오프라인 폐기 실패를 화면에 표시한다.

## 실행

작업 worktree에서 기존 전용 스택을 사용한다. 공유 `yai-hub` DB는 사용하지 않는다.

```sh
supabase start --exclude edge-runtime,imgproxy,mailpit,postgres-meta,realtime,storage-api,studio,logflare,vector,supavisor
supabase migration up --local
.venv/bin/python supabase/tests/seed_portal.py
.venv/bin/python supabase/tests/seed_hospital_care.py
npm run build --prefix apps/portal_web
.venv/bin/python scripts/run_local_portal.py
```

현재 이 작업의 Docker DB/API 포트는 `127.0.0.1:54339`, `127.0.0.1:54341`로 제한했다. Supabase CLI가 컨테이너를 새로 만들면 기본 바인딩이 모든 인터페이스일 수 있으므로 재확인해야 한다. 웹은 `127.0.0.1:8766`에만 바인딩한다.

seed는 고정 UUID와 `ON CONFLICT DO NOTHING`으로 기존 행을 덮어쓰지 않는다. SQLite도 빈 초기 공간에만 채운다. 기존 `workspace.sqlite3`는 보존하고 가상 계정용 `portal-workspace.sqlite3`를 사용한다. runtime 환경 파일은 Git 제외·0600이며 관리 키는 기록하지 않는다.

## 검증

- 프론트 단위·회귀 40개 및 TypeScript/Vite build.
- Python 보호자 API 11개: 무로그인·병원·다른 소유자·폐기 응답·Auth 장애·루프백/Origin·자료 보존·음성 실패 처리.
- `supabase/tests/local_portal_http_smoke.py`: 실제 두 계정 로그인, 역할별 환자·연결·기억/병원 사실 범위, Studio 직접 접근, 로그아웃 후 동일 JWT의 GET/PATCH 거부.
- 브라우저에서 양쪽 로그인·자료·역할 경계·갱신을 확인한다. 최종 스크린샷을 같은 폴더에 보관한다.
- Astra high 재검토: 잔여 HIGH/MEDIUM 없음. 병원 호버 스타일은 링크·버튼 모두 파란 팔레트를 사용하도록 보완.
- architecture 생성·검사, 생성기 단위검사, diff 공백 검사.

## 제한과 안전 영향

보호자 스튜디오의 편집 자료는 SQLite이며 현재 환자 iPad·Supabase 가족 기억 RAG로 동기화하지 않는다. 병원 연결 탭에 별도 기억 편집기를 두지 않는다. 외부 음성/대화 공급자 키가 없어 복제 음성과 유료 대화 생성은 검증하지 않았다. 음성 생성·기기 전달 성공을 fixture로 위장하지 않는다.

이번 변경은 가상 자료와 역할 접근 범위이며 환자용 응답 정책은 변경하지 않았다. 실제 환자 적용 전에는 원격 전용 프로젝트 설정, 계정별 저장소, 기관·동의·임상 검토가 필요하다. 원격 배포·푸시·병합은 하지 않았다.
