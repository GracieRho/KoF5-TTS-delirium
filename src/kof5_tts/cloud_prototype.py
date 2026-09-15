"""Phase-0 hosted speech pipeline for synthetic, consented test material only."""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote

import httpx


@dataclass(frozen=True)
class CloudCredentials:
    deepgram_key: str
    openai_key: str
    elevenlabs_key: str
    voice_id: str
    voice_owner_consent_verified: bool

    def __post_init__(self) -> None:
        if not all((self.deepgram_key, self.openai_key, self.elevenlabs_key, self.voice_id)):
            raise ValueError("all hosted API credentials and a voice ID are required")
        if not self.voice_owner_consent_verified:
            raise ValueError("voice owner's cloning consent must be verified")


def transcribe_wav(client: httpx.Client, wav: bytes, key: str) -> str:
    """Deepgram Nova-3 batch STT; streaming is a later, measured step."""
    if not wav.startswith(b"RIFF") or len(wav) > 2_000_000:
        raise ValueError("expected a short WAV under 2 MB")
    response = client.post(
        "https://api.deepgram.com/v1/listen",
        params={"model": "nova-3", "language": "ko", "mip_opt_out": "true"},
        headers={"Authorization": f"Token {key}", "Content-Type": "audio/wav"},
        content=wav,
    )
    response.raise_for_status()
    try:
        transcript = response.json()["results"]["channels"][0]["alternatives"][0]["transcript"]
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise ValueError("STT response has no transcript") from exc
    if not isinstance(transcript, str) or not transcript.strip():
        raise ValueError("STT returned empty speech")
    return transcript.strip()


def generate_short_reply(client: httpx.Client, transcript: str, known_fact: str, key: str) -> str:
    """A stateless synthetic Korean reply; output still needs human review."""
    if not transcript.strip() or not known_fact.strip():
        raise ValueError("speech and a verified synthetic fact are required")
    response = client.post(
        "https://api.openai.com/v1/responses",
        headers={"Authorization": f"Bearer {key}"},
        json={
            "model": "gpt-5.4-mini",
            "store": False,
            "max_output_tokens": 150,
            "instructions": (
                "ROLE: 가족 목소리로 읽힐 짧은 한국어 답을 만든다. 실제 가족 본인이나 전화 연결이라고 주장하지 않는다. "
                "SAFETY: 의료 진단·약물 결정 금지. 병원·가족 사실을 추측하지 않는다. 모르면 모른다고 한다. "
                "KNOWN FACTS: 아래 확인된 합성 사실만 참고한다. "
                "CONVERSATION: 1~2개의 짧은 문장으로 답한다."
            ),
            "input": f"확인된 합성 사실: {known_fact}\n환자 역할 발화: {transcript}",
        },
    )
    response.raise_for_status()
    try:
        output = response.json()["output"]
        text = "".join(
            part["text"]
            for item in output if item.get("type") == "message"
            for part in item.get("content", []) if part.get("type") == "output_text"
        ).strip()
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("LLM response has no text") from exc
    if not text or len(text) > 200:
        raise ValueError("LLM response is empty or too long")
    return text


def synthesize_mp3(client: httpx.Client, text: str, credentials: CloudCredentials) -> bytes:
    """ElevenLabs Korean-capable IVC voice playback, never enrollment here."""
    if not text.strip() or len(text) > 200:
        raise ValueError("TTS text must be short")
    response = client.post(
        f"https://api.elevenlabs.io/v1/text-to-speech/{quote(credentials.voice_id, safe='')}",
        headers={"xi-api-key": credentials.elevenlabs_key},
        json={"text": text, "model_id": "eleven_multilingual_v2"},
    )
    response.raise_for_status()
    if not response.content:
        raise ValueError("TTS returned no audio")
    return response.content


def run_synthetic_pipeline(
    client: httpx.Client, wav: bytes, known_fact: str, credentials: CloudCredentials
) -> tuple[str, str, bytes]:
    """Keep the WAV and generated MP3 in memory; callers decide if they may save them."""
    transcript = transcribe_wav(client, wav, credentials.deepgram_key)
    reply = generate_short_reply(client, transcript, known_fact, credentials.openai_key)
    audio = synthesize_mp3(client, reply, credentials)
    return transcript, reply, audio
