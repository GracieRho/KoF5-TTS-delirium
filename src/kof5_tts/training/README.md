# Training

F5-TTS를 한국어 화자 zero-shot 클로닝에 맞게 파인튜닝하는 코드를 둡니다. 학습 실행은 공식 F5-TTS(`CFM`, `DiT`, `Trainer`)를 그대로 사용하고, 이 모듈은 그 위에 vocab 확장과 단계별 부분 학습만 얹습니다.

## 왜 단계를 나누는가

F5-TTS v1 Base의 파라미터는 약 338M이며 구성은 다음과 같습니다.

| 그룹 | 파라미터 이름 접두사 | 크기 | 비중 |
| --- | --- | --- | --- |
| `text_embedding` | `transformer.text_embed.text_embed.` | 2.6M | 0.8% |
| `text_encoder` | `transformer.text_embed.text_blocks.` | 4.2M | 1.2% |
| `time_embedding` | `transformer.time_embed.` | 1.3M | 0.4% |
| `input_embedding` | `transformer.input_embed.` | 4.8M | 1.4% |
| `dit_blocks:0-21` | `transformer.transformer_blocks.` | 323M | 95.5% |
| `output_head` | `transformer.norm_out.`, `transformer.proj_out.` | 2.2M | 0.7% |

한국어 적응에 반드시 필요한 부분은 `text_embedding`과 `text_encoder`이며 전체의 2%입니다. 확장한 vocab의 새 문자 행은 무작위로 초기화되므로 학습이 필요하고, ConvNeXt 텍스트 인코더는 텍스트를 음성 프레임에 정렬하므로 한국어 음운 배열을 학습해야 합니다.

반면 화자 유사도는 별도 speaker embedding이 아니라 참조 음성을 문맥으로 사용하는 infilling으로 구현되므로, DiT 블록의 클로닝 능력은 언어와 무관하게 이미 학습되어 있다고 보고 1단계에서는 동결합니다.

## 실험 단계

| 설정 | 학습 대상 | 학습 파라미터 | 목적 |
| --- | --- | --- | --- |
| 기준선 | 없음 | 0 | 바닐라 F5-TTS의 SECS 하한 |
| `stage1_text_only.yaml` | 텍스트 임베딩, 텍스트 인코더 | 6.9M (2.0%) | 최소 비용 한국어 적응 |
| `stage2_text_shallow_dit.yaml` | 1단계 + DiT 0–5 | 95.0M (28.1%) | 앞쪽 블록의 기여 검증 |
| `stage3_full.yaml` | 전체 | 338M (100%) | 성능 상한 확인 |

2단계의 블록 범위는 가정이며 검증 대상입니다. `dit_blocks:16-21`처럼 범위를 바꿔가며 비교하면 한국어 합성에 기여하는 블록 위치를 확인할 수 있고, 그 결과는 이후 프루닝 대상 선정에 사용합니다.

## 실행 순서

1단계로 사전학습 vocab에 한국어 문자를 더하고 체크포인트의 텍스트 임베딩 행을 함께 늘립니다. 공식 `Trainer`는 state dict를 strict 모드로 로드하므로 이 변환 없이는 학습이 시작되지 않습니다.

```bash
python3 scripts/extend_vocab.py \
  checkpoints/pretrained/F5TTS_v1_Base/vocab.txt \
  data/processed/manifests/ko_pilot/metadata.csv \
  checkpoints/pretrained/F5TTS_v1_Base/model_1250000.safetensors \
  data/processed/manifests/ko_pilot
```

이어서 공식 전처리로 학습 입력을 만들고 단계별 학습을 실행합니다.

```bash
python3 <F5-TTS>/src/f5_tts/train/datasets/prepare_csv_wavs.py \
  data/processed/manifests/ko_pilot/metadata.csv \
  data/processed/manifests/ko_pilot

accelerate launch --mixed_precision=fp16 \
  scripts/finetune_f5.py configs/finetuning/stage1_text_only.yaml
```

체크포인트는 `checkpoints/finetuned/<run_name>/`에 저장되며 Git에서 제외됩니다. 공유 기준은 [`checkpoints/README.md`](../../../checkpoints/README.md)를 따릅니다.

## 평가

같은 조건에서 기준선과 각 단계를 비교합니다. 평가 화자는 학습에 포함되지 않은 화자만 사용합니다.

```bash
python3 scripts/eval_secs.py data/processed/manifests/ko_pilot/eval.tsv --tag baseline
python3 scripts/eval_secs.py data/processed/manifests/ko_pilot/eval.tsv --tag s1 \
  --checkpoint checkpoints/finetuned/s1-text-only/model_last.pt \
  --vocab data/processed/manifests/ko_pilot/vocab.txt
```

`--checkpoint`를 생략하면 사전학습 모델로 기준선을 측정합니다. 지표는 생성 음성과 프롬프트의 유사도, 생성 음성과 같은 화자의 다른 실제 발화의 유사도 두 가지이며, 프롬프트의 음향 특성을 그대로 따라가도 점수가 오를 수 있으므로 후자를 주 지표로 봅니다.
