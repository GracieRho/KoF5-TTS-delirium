"""ASGI entrypoint for Favilium's voice-only workspace."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent / "src"))
from kof5_tts.voice_only import app  # noqa: E402
