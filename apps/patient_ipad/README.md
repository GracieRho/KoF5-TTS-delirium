# iPad 마이크 내부 시험

Flutter/`record`의 16 kHz mono PCM 스트림으로 기기 내 발화 **후보**를 감지합니다. 1초 이내의 휘발성 직전 버퍼와 최대 8초 후보만 메모리에 두고, 후보 발생 시 오디오를 폐기합니다. 환자 목소리 등록·화자 판정, 서버 전송, 대화·TTS 기능은 아직 없습니다. 에너지 임계값은 실제 병실 평가 전에 사용할 수 없습니다.

`flutter test`와 `flutter analyze`로 로직을 확인할 수 있습니다. 실제 iPad 마이크·권한·중단 동작은 기기 실행 후 따로 검증해야 합니다. 이 화면은 내부/자가 음성 시험 전용이며 [안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md) 통과 전 실제 환자에게 사용하지 않습니다.
