# 자동 생성 프로젝트 구조도

이 파일은 `scripts/generate_architecture.py`가 코드·설정 목록과 정해진 MVP 목표 흐름에서 생성합니다. 구조도는 구현 완료를 뜻하지 않습니다. 직접 수정하지 않습니다.

```mermaid
flowchart LR
  mic["보호자 녹음"] --> enroll["ElevenLabs 목소리 등록"]
  enroll --> voice["등록된 목소리"]
  voice --> tts["ElevenLabs 음성 합성"]
  text["입력한 문장"] --> tts
  tts --> mp3["재생 및 MP3 저장"]

  subgraph code["코드 레이어"]
    layer_root["root (1)"]
    layer_voice_only["voice_only (1)"]
    layer_voice_store["voice_store (1)"]
    layer_voice_only --> layer_voice_store
  end
```

## 현재 카탈로그

- Python 모듈: **3**
- 설정 파일: **0**
- 프로젝트 실행 스크립트: **1**

### Python 모듈

| Module | Layer | Path | Internal imports |
| --- | --- | --- | --- |
| `kof5_tts` | root | `src/kof5_tts/__init__.py` | — |
| `kof5_tts.voice_only` | voice_only | `src/kof5_tts/voice_only.py` | `kof5_tts.voice_store` |
| `kof5_tts.voice_store` | voice_store | `src/kof5_tts/voice_store.py` | — |

### 설정 파일

아직 확정된 설정 파일이 없습니다.

### 실행 스크립트

| Path |
| --- |
| `scripts/run_backend.py` |

## 분석 한계

- Python의 정적 import만 분석합니다.
- 동적 import와 런타임 모델 연결은 수동 검토가 필요합니다.
- 데이터와 체크포인트 내용은 안전을 위해 읽거나 목록화하지 않습니다.
