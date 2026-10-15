Browser tab: 4, Title: "Favilium · 병원", URL: "http://127.0.0.1:8766/hospital".
0 AXWebArea Favilium · 병원, URL: 127.0.0.1:8766/hospital
	1 container root
		2 link Description: Favilium, Value: 127.0.0.1:8766/hospital
		3 container 병동 돌봄 메뉴
			4 button 돌봄 현황
			5 button 담당 환자
			6 button 음성·전달 일정
			7 button 인계·주의 사항
			8 button 환자 등록
			9 button 로그아웃
		10 container
			11 text 병동 돌봄 / 김하늘 병동팀
			12 button ← 환자 목록
			13 container
				14 heading 김하늘, Value: 1
					15 text 김하늘
				16 text 햇살병동  ·  301호 1번 침상 환자 번호  TEST-FV-001
				17 button 평가 기록 추가
			18 tab group 환자 돌봄 업무
				19 tab (selectable, settable, boolean) 환자 개요, Value: 0, ID: care-tab-overview
				20 tab (selectable, settable, boolean) 평가·관찰, Value: 0, ID: care-tab-observations
				21 tab (selectable, settable, boolean) 돌봄 계획 4, Value: 0, ID: care-tab-plan
				22 tab (selected, settable, boolean) 가족 음성, Value: 1, ID: care-tab-voice
				23 tab (selectable, settable, boolean) 인계·이력 1, Value: 0, ID: care-tab-handoff
			24 container Description: 가족 음성, ID: care-panel-voice
				25 heading 가족 목소리와 사용 계획, Value: 2
					26 text 가족 목소리와 사용 계획
				27 button (collapsed) Description: 가족 음성 도움말, Secondary Actions: Expand
				28 button 음성 계획 추가
				29 container
					30 text 가족 연결 확인됨
					31 button (collapsed) Description: 재생 준비 도움말, Secondary Actions: Expand
					32 text 재생 연결 확인 전
				33 content list
					34 container
						35 text 날짜·장소 안내
						36 heading 2026. 10. 16. 00:50 (한국 시간) · 3분, Value: 3
							37 text 2026. 10. 16. 00:50 (한국 시간)  ·  분
						38 text 하늘님, 오늘 가족과 함께 찍었던 봄 사진 이야기를 잠깐 나누려고 해요. 원하실 때만 편하게 들어주세요. 확인 담당 ·  병동팀 취소 사유 ·  가상 자료 검증 중 입력 시각을 재확인하기 위해 취소했습니다. 취소됨
					39 container
						40 text 날짜·장소 안내
						41 heading 2026. 10. 16. 09:00 (한국 시간) · 3분, Value: 3
							42 text 2026. 10. 16. 09:00 (한국 시간)  ·  분
						43 text 지금 계신 장소를 천천히 안내하고 편안한 가족 이야기를 짧게 나눕니다. 확인 담당 ·  병동팀 계획 저장됨
						44 button 계획 취소
					45 container
						46 text 날짜·장소 안내
						47 heading 2026. 10. 16. 10:30 (한국 시간) · 3분, Value: 3
							48 text 2026. 10. 16. 10:30 (한국 시간)  ·  분
						49 text 가족 사진 이야기를 짧게 함께 나누고, 환자 의사에 따라 중단할 계획입니다. 확인 담당 ·  병동팀 계획 저장됨
						50 button 계획 취소

The focused UI element is 22 tab (selected, settable, boolean) 가족 음성, Value: 1, ID: care-tab-voice