"""Tiny valid silent PCM WAV for mocked provider and API checks."""

from io import BytesIO
import wave

stream = BytesIO()
with wave.open(stream, "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(16_000)
    audio.writeframes(b"\0" * 3_200)
SYNTHETIC_WAV = stream.getvalue()
