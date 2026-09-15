"""사전학습 vocab에 한국어 문자를 덧붙이고 text embedding 행을 확장한다."""

from __future__ import annotations

import csv
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import torch

TEXT_EMBED_SUFFIX = "transformer.text_embed.text_embed.weight"
INIT_STD = 0.02


class VocabError(RuntimeError):
    """vocab 확장 또는 체크포인트 변환이 실패했을 때 발생한다."""


@dataclass(frozen=True)
class VocabExtension:
    base_size: int
    added: tuple[str, ...]
    expanded_tensors: int

    @property
    def new_size(self) -> int:
        return self.base_size + len(self.added)


def read_vocab(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines:
        raise VocabError(f"vocab 파일이 비어 있습니다: {path}")
    return lines


def characters_in_manifest(path: Path, normalization: str = "NFC") -> set[str]:
    characters: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="|")
        header = next(reader, None)
        if header is None:
            raise VocabError(f"manifest가 비어 있습니다: {path}")
        for row in reader:
            if len(row) < 2:
                continue
            characters.update(unicodedata.normalize(normalization, row[1]))
    return characters


def new_characters(base: Iterable[str], observed: Iterable[str]) -> tuple[str, ...]:
    known = set(base)
    return tuple(sorted(character for character in observed if character not in known))


def expand_text_embedding(state_dict: dict[str, "torch.Tensor"], added: int) -> int:
    import torch

    expanded = 0
    for key, tensor in list(state_dict.items()):
        if not key.endswith(TEXT_EMBED_SUFFIX):
            continue
        padding = torch.randn(added, tensor.shape[1], dtype=tensor.dtype) * INIT_STD
        state_dict[key] = torch.cat([tensor, padding], dim=0)
        expanded += 1
    if expanded == 0:
        raise VocabError(f"체크포인트에서 {TEXT_EMBED_SUFFIX}로 끝나는 텐서를 찾지 못했습니다.")
    return expanded


def load_state_dict(path: Path) -> dict[str, "torch.Tensor"]:
    import torch

    if path.suffix == ".safetensors":
        from safetensors.torch import load_file

        return load_file(str(path))
    checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    if "ema_model_state_dict" not in checkpoint:
        raise VocabError(f"ema_model_state_dict가 없습니다: {path}")
    return checkpoint["ema_model_state_dict"]


def save_state_dict(state_dict: dict[str, "torch.Tensor"], path: Path) -> None:
    from safetensors.torch import save_file

    save_file({key: value.contiguous() for key, value in state_dict.items()}, str(path))


def extend(base_vocab: Path, manifest: Path, checkpoint: Path, output_dir: Path) -> VocabExtension:
    """확장된 vocab.txt와 임베딩을 늘린 safetensors 체크포인트를 만든다."""

    base = read_vocab(base_vocab)
    added = new_characters(base, characters_in_manifest(manifest))

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "vocab.txt").write_text("\n".join([*base, *added]) + "\n", encoding="utf-8")

    state_dict = load_state_dict(checkpoint)
    expanded = expand_text_embedding(state_dict, len(added))
    save_state_dict(state_dict, output_dir / "pretrained_model_ko_init.safetensors")

    return VocabExtension(len(base), added, expanded)
