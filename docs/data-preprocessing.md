# AI Hub 데이터 다운로드와 오디오 전처리

AI Hub에서 승인된 데이터셋을 내려받고, 포함된 WAV를 학습 인계 규격인 **24 kHz, mono, 16-bit FLAC**으로 변환하는 절차입니다. 실제 음성, API key와 다운로드 산출물은 Git에 커밋하지 않습니다.

이 절차는 기존 모델 연구용 도구입니다. [클라우드 중심 제품 MVP](Delirium_Familiar_Voice_MVP_PRD.md)나 실제 환자 대상 데이터 처리 절차를 뜻하지 않습니다.

## 1. 사전 준비

- AI Hub 데이터셋 상세 페이지에서 다운로드 신청과 승인을 완료합니다.
- `ffmpeg`와 `ffprobe`를 설치합니다. macOS에서는 `brew install ffmpeg`를 사용할 수 있습니다.
- [AI Hub 공식 안내](https://aihub.or.kr/devsport/apishell/list.do?currMenu=528&topMenu=100)에서 `aihubshell`을 내려받습니다.

공식 안내의 `/usr/bin` 복사는 Linux 기준입니다. macOS의 `/usr/bin`은 SIP 보호 영역이므로 사용자 PATH에 포함된 디렉터리를 사용합니다.

```bash
chmod +x ~/aihubshell
mkdir -p ~/.local/bin
cp ~/aihubshell ~/.local/bin/aihubshell
aihubshell -help
```

AI Hub가 2026-08-18에 배포한 `aihubshell v0.6`은 GNU `grep -P`, GNU `sort -z/-V`를 사용하므로 macOS 기본 명령과 호환되지 않습니다. `grep: invalid option -- P`가 보이거나 분할 파일 병합이 실패하면 macOS 호환본을 사용해야 합니다. 현재 개발 Mac의 `~/.local/bin/aihubshell`에는 help 파싱, 숫자 part 병합과 curl 실패 전파 호환 수정이 적용되어 있습니다.

## 2. API key 보관

저장소 루트의 로컬 `.env`에 다음 한 줄을 둡니다. 스크립트는 이미 설정된 환경변수를 우선하고, 없으면 `.env`에서 값을 읽습니다. 값은 `aihubshell`의 명령행 인자로 전달하지 않으므로 shell history와 프로세스 인자에 남지 않습니다.

```dotenv
AIHUB_APIKEY=발급받은_키
```

`.env`는 Git에서 제외됩니다. 공유 예시는 `.env.example`만 사용합니다.

```bash
chmod 600 .env
```

## 3. 데이터셋과 file key 확인

```bash
python3 scripts/download_aihub.py list
python3 scripts/download_aihub.py list --dataset-key <DATASET_KEY>
```

첫 명령의 데이터셋 제목과 key를 확인한 뒤 두 번째 명령으로 파일명, 크기와 file key를 확인합니다. 다운로드에는 원본 압축 크기의 2~3배 여유 공간이 필요하다는 AI Hub 안내를 따릅니다.

## 4. 다운로드와 변환

전체 데이터셋 다운로드:

```bash
python3 scripts/download_aihub.py download --dataset-key <DATASET_KEY>
```

필요한 파일만 선택 다운로드:

```bash
python3 scripts/download_aihub.py download \
  --dataset-key <DATASET_KEY> \
  --file-key <FILE_KEY_1> \
  --file-key <FILE_KEY_2>
```

다운로드부터 FLAC 변환까지 한 번에 실행:

```bash
python3 scripts/run_preprocessing_pipeline.py \
  --dataset-key <DATASET_KEY> \
  --file-key <FILE_KEY> \
  --jobs 4
```

기본 경로는 다음과 같습니다.

- AI Hub 원본: `data/raw/aihub/<DATASET_KEY>/`
- 변환 결과: `data/interim/flac/<DATASET_KEY>/`

이미 받은 데이터에서 변환만 다시 실행할 때는 `--skip-download`를 사용합니다. 기존 FLAC은 규격을 검증한 뒤 건너뛰며, 원본이 더 최신이면 실수로 덮지 않고 실패합니다. 의도적으로 다시 만들 때만 `--overwrite`를 추가합니다.

AI Hub 이외의 WAV 디렉터리만 변환할 수도 있습니다.

```bash
python3 scripts/convert_wav_to_flac.py \
  --input data/raw/wav \
  --output data/interim/flac \
  --jobs 4
```

각 결과는 `ffprobe`로 FLAC codec, 24,000 Hz, 1 channel, signed 16-bit를 검증한 뒤 최종 경로로 원자적으로 이동합니다. 입력의 하위 디렉터리 구조와 파일명은 유지하고 확장자만 `.flac`으로 바꿉니다.

## 안전·인계 메모

- 데이터 이용 범위와 재배포 조건은 해당 AI Hub 데이터셋 라이선스를 확인합니다.
- 실제 임상 음성, 환자 식별정보나 비공개 연구 데이터에는 이 일반 다운로드 경로를 사용하지 않습니다.
- 이 변경은 임상 문구나 환자 대상 동작을 바꾸지 않으므로 별도 임상 문구 검토 대상은 아닙니다.
- 별도 모델 연구를 재개할 때에만 검증을 통과한 `data/interim/flac/` 경로와 별도 manifest를 인계합니다.
