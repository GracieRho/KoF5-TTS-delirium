"""Vercel's ASGI entrypoint for the synthetic-only FastAPI prototype."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent / "src"))

from kof5_tts.api import app  # noqa: E402
