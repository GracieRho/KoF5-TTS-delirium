"""F5-TTS 파라미터를 이름 기준 그룹으로 나누고 단계별로 학습 대상을 고른다."""

from __future__ import annotations

import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import torch

GROUP_PREFIXES: dict[str, tuple[str, ...]] = {
    "text_embedding": ("transformer.text_embed.text_embed.",),
    "text_encoder": ("transformer.text_embed.text_blocks.",),
    "time_embedding": ("transformer.time_embed.",),
    "input_embedding": ("transformer.input_embed.",),
    "output_head": ("transformer.norm_out.", "transformer.proj_out."),
}

_BLOCK_SPEC = re.compile(r"^dit_blocks:(\d+)-(\d+)$")
_BLOCK_NAME = re.compile(r"^transformer\.transformer_blocks\.(\d+)\.")


class ParamGroupError(ValueError):
    """학습 대상 지정이 잘못되었을 때 발생한다."""


@dataclass(frozen=True)
class FreezeSummary:
    trainable_groups: tuple[str, ...]
    trainable_parameters: int
    frozen_parameters: int

    @property
    def trainable_ratio(self) -> float:
        total = self.trainable_parameters + self.frozen_parameters
        return self.trainable_parameters / total if total else 0.0


def _block_range(spec: str) -> range:
    matched = _BLOCK_SPEC.match(spec)
    if not matched:
        raise ParamGroupError(f"알 수 없는 학습 대상입니다: {spec}")
    start, end = int(matched.group(1)), int(matched.group(2))
    if start > end:
        raise ParamGroupError(f"블록 범위가 뒤집혔습니다: {spec}")
    return range(start, end + 1)


def resolve_targets(targets: Sequence[str], depth: int) -> tuple[set[str], set[int]]:
    prefixes: set[str] = set()
    blocks: set[int] = set()
    for target in targets:
        if target == "all":
            every = {prefix for group in GROUP_PREFIXES.values() for prefix in group}
            return every, set(range(depth))
        if target in GROUP_PREFIXES:
            prefixes.update(GROUP_PREFIXES[target])
            continue
        selected = _block_range(target)
        if selected.stop > depth:
            raise ParamGroupError(f"블록 인덱스가 depth({depth})를 넘습니다: {target}")
        blocks.update(selected)
    return prefixes, blocks


def is_trainable(name: str, prefixes: Iterable[str], blocks: set[int]) -> bool:
    if any(name.startswith(prefix) for prefix in prefixes):
        return True
    matched = _BLOCK_NAME.match(name)
    return matched is not None and int(matched.group(1)) in blocks


def apply_freeze(model: "torch.nn.Module", targets: Sequence[str], depth: int) -> FreezeSummary:
    """지정한 그룹만 requires_grad를 남기고 나머지를 동결한다."""

    if not targets:
        raise ParamGroupError("학습 대상 그룹이 비어 있습니다.")
    prefixes, blocks = resolve_targets(targets, depth)

    trainable = frozen = 0
    for name, parameter in model.named_parameters():
        if is_trainable(name, prefixes, blocks):
            parameter.requires_grad_(True)
            trainable += parameter.numel()
        else:
            parameter.requires_grad_(False)
            frozen += parameter.numel()

    if trainable == 0:
        raise ParamGroupError("학습 대상으로 선택된 파라미터가 없습니다. 이름 규칙을 확인하세요.")
    return FreezeSummary(tuple(targets), trainable, frozen)
