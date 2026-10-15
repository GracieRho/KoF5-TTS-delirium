Browser tab: 2, Title: "Favilium", URL: "http://127.0.0.1:8766/studio?tab=chat".
0 AXWebArea Favilium, URL: 127.0.0.1:8766/studio?tab=chat
	1 container root
		2 link Description: Favilium, Value: 127.0.0.1:8766/studio
		3 container
			4 text 가족의 공간
			5 container 가족의 공간 메뉴
				6 button 함께 시작하기
				7 button 목소리 등록
				8 button 가족의 기억 6
					9 text 가족의 기억
					10 text 6
				11 button 대화해보기
				12 button 병원 연결
				13 button 로그아웃
		14 container
			15 text 가족의 공간 / 대화해보기
			16 heading 목소리로 대화하기, Value: 1
				17 text 목소리로 대화하기
			18 text 등록 후 사용할 수 있어요
			19 heading 김서연님의 목소리와 함께, Value: 2
				20 text 김서연님의 목소리와 함께
			21 text AI 대화
			22 button (collapsed) Description: AI 대화 도움말, Secondary Actions: Expand
			23 text 가족 소개, 일반 기억 한 건, 복제 음성과 공급자 연결을 먼저 준비해주세요.
			24 container
				25 checkbox (settable, integer) Description: 기억·질문을 OpenAI에, 답변을 ElevenLabs에 전송합니다. 마이크 질문은 Deepgram에서 전사하는 데 동의합니다., Value: 0
				26 text 대화할 질문
				27 text entry area (disabled) 대화할 질문, ID: conversation-question
				28 button (disabled) 말로 질문
				29 text 지금은 글로 질문할 수 있어요
				30 button (disabled) 답변 만들기

The focused UI element is 11 button 대화해보기