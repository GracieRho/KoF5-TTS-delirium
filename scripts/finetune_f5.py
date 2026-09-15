#!/usr/bin/env python3
"""configs/finetuning의 설정으로 F5-TTS를 단계별 부분 파인튜닝한다."""

from __future__ import annotations

import argparse
from pathlib import Path

import yaml
from _bootstrap import REPOSITORY_ROOT
from f5_tts.model import CFM, DiT, Trainer
from f5_tts.model.dataset import load_dataset
from f5_tts.model.utils import get_tokenizer

from kof5_tts.training.param_groups import apply_freeze

MODEL_CFG = dict(dim=1024, depth=22, heads=16, ff_mult=2, text_dim=512, conv_layers=4)
MEL_CFG = dict(
    n_fft=1024,
    hop_length=256,
    win_length=1024,
    n_mel_channels=100,
    target_sample_rate=24000,
    mel_spec_type="vocos",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--dataset-name", help="설정 파일 값을 덮어쓴다")
    return parser.parse_args()


def build_model(vocab_path: Path) -> tuple[CFM, int]:
    vocab_char_map, vocab_size = get_tokenizer(str(vocab_path), "custom")
    model = CFM(
        transformer=DiT(**MODEL_CFG, text_num_embeds=vocab_size, mel_dim=MEL_CFG["n_mel_channels"]),
        mel_spec_kwargs=MEL_CFG,
        vocab_char_map=vocab_char_map,
    )
    return model, vocab_size


def main() -> int:
    args = parse_args()
    config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    dataset_name = args.dataset_name or config["dataset_name"]
    run_dir = REPOSITORY_ROOT / "checkpoints" / "finetuned" / config["run_name"]
    run_dir.mkdir(parents=True, exist_ok=True)

    vocab_path = REPOSITORY_ROOT / config["vocab_path"]
    model, vocab_size = build_model(vocab_path)
    summary = apply_freeze(model, config["trainable_groups"], MODEL_CFG["depth"])

    print(f"vocab: {vocab_size}")
    print(f"trainable groups: {', '.join(summary.trainable_groups)}")
    print(
        f"trainable: {summary.trainable_parameters / 1e6:.1f}M / "
        f"total: {(summary.trainable_parameters + summary.frozen_parameters) / 1e6:.1f}M "
        f"({summary.trainable_ratio:.1%})"
    )

    trainer = Trainer(
        model,
        epochs=config["epochs"],
        learning_rate=float(config["learning_rate"]),
        num_warmup_updates=config["num_warmup_updates"],
        save_per_updates=config["save_per_updates"],
        keep_last_n_checkpoints=config.get("keep_last_n_checkpoints", 3),
        checkpoint_path=str(run_dir),
        batch_size_per_gpu=config["batch_size_per_gpu"],
        batch_size_type=config.get("batch_size_type", "frame"),
        max_samples=config.get("max_samples", 32),
        grad_accumulation_steps=config.get("grad_accumulation_steps", 1),
        max_grad_norm=config.get("max_grad_norm", 1.0),
        logger=config.get("logger", "tensorboard"),
        wandb_project="kof5-tts",
        wandb_run_name=config["run_name"],
        last_per_updates=config.get("last_per_updates", 5000),
        mel_spec_type=MEL_CFG["mel_spec_type"],
        model_cfg_dict=config,
    )
    trainer.train(load_dataset(dataset_name, "custom", mel_spec_kwargs=MEL_CFG))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
