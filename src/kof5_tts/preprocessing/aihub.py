"""AI Hub 공식 aihubshell을 안전하게 호출한다."""

from __future__ import annotations

import fcntl
import os
import re
import shutil
import subprocess
from collections import deque
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path

SUCCESS_MARKER = "병합이 완료 되었습니다."
_KEY_PATTERN = re.compile(r"^[0-9]+$")


class AihubError(RuntimeError):
    """AI Hub CLI 실행이 실패했을 때 발생한다."""


@dataclass(frozen=True)
class DownloadResult:
    dataset_key: str
    file_keys: tuple[str, ...]
    output_dir: Path


def _read_env_value(path: Path, key: str) -> str | None:
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        name, separator, raw_value = line.partition("=")
        if not separator or name.strip() != key:
            continue
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        return value
    return None


def environment_with_api_key(
    *,
    env_file: Path | None = None,
    search_roots: Iterable[Path] = (),
    environ: Mapping[str, str] | None = None,
) -> dict[str, str]:
    """환경변수를 우선하고, 없으면 지정된 로컬 .env에서 API 키를 읽는다."""

    environment = dict(os.environ if environ is None else environ)
    if environment.get("AIHUB_APIKEY", "").strip():
        return environment

    candidates = [env_file] if env_file else [root / ".env" for root in search_roots]
    for candidate in candidates:
        if candidate is None or not candidate.is_file():
            continue
        value = _read_env_value(candidate, "AIHUB_APIKEY")
        if value and value.strip():
            environment["AIHUB_APIKEY"] = value.strip()
            return environment
    searched = ", ".join(str(path) for path in candidates if path is not None)
    suffix = f" 확인 경로: {searched}" if searched else ""
    raise AihubError(f"AIHUB_APIKEY를 환경변수 또는 로컬 .env에서 찾지 못했습니다.{suffix}")


def _validate_key(value: str, label: str) -> str:
    normalized = value.strip()
    if not _KEY_PATTERN.fullmatch(normalized):
        raise AihubError(f"{label}는 숫자만 사용할 수 있습니다: {value!r}")
    return normalized


def normalize_file_keys(values: Iterable[str]) -> tuple[str, ...]:
    keys: list[str] = []
    for value in values:
        for item in value.split(","):
            if item.strip():
                key = _validate_key(item, "file key")
                if key not in keys:
                    keys.append(key)
    return tuple(keys)


def resolve_cli(override: str | None = None) -> str:
    candidate = override or shutil.which("aihubshell")
    if not candidate:
        raise AihubError(
            "aihubshell을 찾지 못했습니다. 공식 파일에 실행 권한을 준 뒤 PATH에 포함된 "
            "~/.local/bin/aihubshell에 설치하세요."
        )
    return candidate


def build_download_command(
    cli: str, dataset_key: str, file_keys: Iterable[str] = ()
) -> tuple[list[str], tuple[str, ...]]:
    dataset_key = _validate_key(dataset_key, "dataset key")
    normalized_file_keys = normalize_file_keys(file_keys)
    command = [cli, "-mode", "d", "-datasetkey", dataset_key]
    if normalized_file_keys:
        command.extend(["-filekey", ",".join(normalized_file_keys)])
    return command, normalized_file_keys


def list_datasets(dataset_key: str | None = None, *, cli: str | None = None) -> str:
    command = [resolve_cli(cli), "-mode", "l"]
    if dataset_key is not None:
        command.extend(["-datasetkey", _validate_key(dataset_key, "dataset key")])
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise AihubError(f"AI Hub 목록 조회 실패: {detail}")
    return completed.stdout


def download_dataset(
    dataset_key: str,
    output_dir: Path,
    *,
    file_keys: Iterable[str] = (),
    cli: str | None = None,
    environ: Mapping[str, str] | None = None,
    on_output: Callable[[str], None] | None = None,
) -> DownloadResult:
    """API 키를 프로세스 인자에 노출하지 않고 데이터셋을 다운로드한다."""

    environment = dict(os.environ if environ is None else environ)
    if not environment.get("AIHUB_APIKEY", "").strip():
        raise AihubError("AIHUB_APIKEY 환경변수가 비어 있습니다.")

    command, normalized_file_keys = build_download_command(
        resolve_cli(cli), dataset_key, file_keys
    )
    normalized_dataset_key = _validate_key(dataset_key, "dataset key")
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    lock_path = output_dir / ".aihubshell.lock"

    with lock_path.open("a+", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise AihubError(f"같은 경로에서 다른 다운로드가 실행 중입니다: {output_dir}") from error

        process = subprocess.Popen(
            command,
            cwd=output_dir,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        tail: deque[str] = deque(maxlen=40)
        success = False
        with process.stdout:
            for line in process.stdout:
                tail.append(line.rstrip())
                success = success or SUCCESS_MARKER in line
                if on_output:
                    on_output(line)
        return_code = process.wait()

    if return_code != 0 or not success:
        detail = "\n".join(item for item in tail if item).strip()
        reason = f"종료 코드 {return_code}" if return_code else f"완료 문구({SUCCESS_MARKER}) 없음"
        raise AihubError(f"AI Hub 다운로드 실패: {reason}\n{detail}".rstrip())
    return DownloadResult(normalized_dataset_key, normalized_file_keys, output_dir)
