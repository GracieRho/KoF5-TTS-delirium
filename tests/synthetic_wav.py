"""Tiny valid silent PCM WAV for mocked provider and API checks."""

from io import BytesIO
import wave

def make_synthetic_wav(seconds: int) -> bytes:
    stream = BytesIO()
    with wave.open(stream, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16_000)
        audio.writeframes(b"\0" * (16_000 * 2 * seconds))
    return stream.getvalue()


SYNTHETIC_WAV = make_synthetic_wav(1)
