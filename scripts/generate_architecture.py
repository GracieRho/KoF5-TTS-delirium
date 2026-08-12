"""Generate deterministic project architecture artifacts.

This is a lightweight adaptation of yai-web's architecture knowledge-map
workflow. It intentionally uses only Python's standard library so it can run
before the TTS framework and project dependencies are selected.
"""

from __future__ import annotations

import argparse
import ast
import json
import re
import tempfile
from collections import defaultdict
from collections.abc import Iterable
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "src" / "kof5_tts"
CONFIG_ROOT = ROOT / "configs"
SCRIPTS_ROOT = ROOT / "scripts"
GENERATED_FILENAMES = ("catalog.json", "project-map.md", "project-map.mmd")
CONFIG_SUFFIXES = {".json", ".toml", ".yaml", ".yml"}
PIPELINE_STAGES = (
    {
        "id": "preprocessing",
        "label": "전처리",
        "input": "data/raw/wav",
        "output": "data/interim/flac + data/processed",
    },
    {
        "id": "training",
        "label": "파인튜닝",
        "input": "data/processed",
        "output": "checkpoints/finetuned",
    },
    {
        "id": "optimization",
        "label": "프루닝·양자화",
        "input": "checkpoints/finetuned",
        "output": "checkpoints/optimized",
    },
    {
        "id": "inference",
        "label": "추론·평가",
        "input": "checkpoints/finetuned 또는 optimized",
        "output": "runs + 평가 문서",
    },
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "architecture" / "generated",
        help="Generated artifact directory.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when committed artifacts differ from a fresh generation.",
    )
    return parser.parse_args()


def module_name(path: Path, source_root: Path = SOURCE_ROOT) -> str:
    relative = path.relative_to(source_root).with_suffix("")
    parts = ["kof5_tts", *relative.parts]
    if parts[-1] == "__init__":
        parts.pop()
    return ".".join(parts)


def module_layer(name: str) -> str:
    parts = name.split(".")
    return parts[1] if len(parts) > 1 else "root"


def resolve_import_from(current: str, imported: str | None, level: int) -> str:
    if level == 0:
        return imported or ""
    current_package = current.split(".")[:-1]
    keep = max(0, len(current_package) - level + 1)
    parts = current_package[:keep]
    if imported:
        parts.extend(imported.split("."))
    return ".".join(parts)


def parse_python_module(path: Path, source_root: Path = SOURCE_ROOT) -> dict[str, Any]:
    name = module_name(path, source_root)
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    imports: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name for alias in node.names if alias.name.startswith("kof5_tts"))
        elif isinstance(node, ast.ImportFrom):
            imported = resolve_import_from(name, node.module, node.level)
            if imported.startswith("kof5_tts"):
                imports.add(imported)
    return {
        "module": name,
        "path": path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else path.name,
        "layer": module_layer(name),
        "imports": sorted(imports),
    }


def python_modules(source_root: Path = SOURCE_ROOT) -> list[dict[str, Any]]:
    if not source_root.exists():
        return []
    return [
        parse_python_module(path, source_root)
        for path in sorted(source_root.rglob("*.py"))
        if "__pycache__" not in path.parts
    ]


def config_files(config_root: Path = CONFIG_ROOT) -> list[dict[str, str]]:
    if not config_root.exists():
        return []
    records = []
    for path in sorted(config_root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in CONFIG_SUFFIXES:
            continue
        relative = path.relative_to(config_root)
        records.append(
            {
                "path": f"configs/{relative.as_posix()}",
                "group": relative.parts[0] if len(relative.parts) > 1 else "root",
            }
        )
    return records


def executable_scripts(scripts_root: Path = SCRIPTS_ROOT) -> list[str]:
    if not scripts_root.exists():
        return []
    return [
        f"scripts/{path.name}"
        for path in sorted(scripts_root.glob("*.py"))
        if not path.name.startswith("test_") and path.name != Path(__file__).name
    ]


def build_catalog() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "project": "KoF5-TTS-delirium",
        "scope": {
            "source": "src/kof5_tts",
            "configs": "configs",
            "scripts": "scripts",
            "generated": "architecture/generated",
        },
        "pipeline": list(PIPELINE_STAGES),
        "python": {"modules": python_modules()},
        "configs": config_files(),
        "scripts": executable_scripts(),
        "limitations": [
            "Python의 정적 import만 분석합니다.",
            "동적 import와 런타임 모델 연결은 수동 검토가 필요합니다.",
            "데이터와 체크포인트 내용은 안전을 위해 읽거나 목록화하지 않습니다.",
        ],
    }


def mermaid_id(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", value)


def markdown_table(headers: list[str], rows: Iterable[list[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(value.replace("|", "\\|") for value in row) + " |")
    return "\n".join(lines)


def render_mermaid(catalog: dict[str, Any]) -> str:
    lines = [
        "flowchart LR",
        '  raw["원본 WAV"] --> preprocess["전처리"]',
        '  preprocess --> flac["중간 FLAC"]',
        '  preprocess --> processed["학습 데이터·manifest"]',
        '  processed --> finetune["파인튜닝"]',
        '  finetune --> tuned["파인튜닝 체크포인트"]',
        '  tuned --> optimize["프루닝·양자화"]',
        '  optimize --> device["온디바이스 후보"]',
        '  tuned --> evaluate["품질·성능 평가"]',
        '  device --> evaluate',
    ]
    modules = catalog["python"]["modules"]
    layers: dict[str, int] = defaultdict(int)
    edges: set[tuple[str, str]] = set()
    for module in modules:
        layers[module["layer"]] += 1
        for imported in module["imports"]:
            target = module_layer(imported)
            if target != module["layer"]:
                edges.add((module["layer"], target))
    if layers:
        lines.extend(["", "  subgraph code[\"코드 레이어\"]"])
        for layer, count in sorted(layers.items()):
            lines.append(f'    layer_{mermaid_id(layer)}["{layer} ({count})"]')
        for source, target in sorted(edges):
            lines.append(f"    layer_{mermaid_id(source)} --> layer_{mermaid_id(target)}")
        lines.append("  end")
    return "\n".join(lines) + "\n"


def render_markdown(catalog: dict[str, Any], mermaid: str) -> str:
    modules = catalog["python"]["modules"]
    configs = catalog["configs"]
    scripts = catalog["scripts"]
    module_rows = [
        [
            f"`{module['module']}`",
            module["layer"],
            f"`{module['path']}`",
            "<br>".join(f"`{item}`" for item in module["imports"]) or "—",
        ]
        for module in modules
    ]
    config_rows = [[item["group"], f"`{item['path']}`"] for item in configs]
    script_rows = [[f"`{item}`"] for item in scripts]
    return f"""# 자동 생성 프로젝트 구조도

이 파일은 `scripts/generate_architecture.py`가 코드와 설정 구조에서 생성합니다. 직접 수정하지 않습니다.

```mermaid
{mermaid.rstrip()}
```

## 현재 카탈로그

- Python 모듈: **{len(modules)}**
- 설정 파일: **{len(configs)}**
- 프로젝트 실행 스크립트: **{len(scripts)}**

### Python 모듈

{markdown_table(["Module", "Layer", "Path", "Internal imports"], module_rows) if module_rows else "아직 구현된 Python 모듈이 없습니다."}

### 설정 파일

{markdown_table(["Group", "Path"], config_rows) if config_rows else "아직 확정된 설정 파일이 없습니다."}

### 실행 스크립트

{markdown_table(["Path"], script_rows) if script_rows else "아직 프로젝트 실행 스크립트가 없습니다."}

## 분석 한계

{chr(10).join(f"- {item}" for item in catalog["limitations"])}
"""


def write_outputs(output: Path, catalog: dict[str, Any]) -> None:
    output.mkdir(parents=True, exist_ok=True)
    mermaid = render_mermaid(catalog)
    payloads = {
        "catalog.json": json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        "project-map.md": render_markdown(catalog, mermaid),
        "project-map.mmd": mermaid,
    }
    for filename, contents in payloads.items():
        (output / filename).write_text(contents.rstrip() + "\n", encoding="utf-8")


def compare_outputs(expected: Path, actual: Path) -> list[str]:
    changed = []
    for filename in GENERATED_FILENAMES:
        expected_path = expected / filename
        actual_path = actual / filename
        if not expected_path.exists() or expected_path.read_bytes() != actual_path.read_bytes():
            changed.append(filename)
    return changed


def main() -> int:
    args = parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="kof5-architecture-") as temporary:
            generated = Path(temporary)
            write_outputs(generated, build_catalog())
            changed = compare_outputs(args.output, generated)
            if changed:
                print("Architecture artifacts are stale: " + ", ".join(changed))
                print("Run: python3 scripts/generate_architecture.py")
                return 1
        print("Architecture artifacts are current.")
        return 0

    if args.output.exists():
        for filename in GENERATED_FILENAMES:
            (args.output / filename).unlink(missing_ok=True)
    write_outputs(args.output, build_catalog())
    try:
        shown_output = args.output.relative_to(ROOT)
    except ValueError:
        shown_output = args.output
    print(f"Generated architecture artifacts in {shown_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
