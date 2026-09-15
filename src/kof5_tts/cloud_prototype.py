"""Phase-0 hosted speech pipeline for synthetic, consented test material only."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from urllib.parse import quote

import httpx

from kof5_tts.companion import ConversationSession, orientation_date


@dataclass(frozen=True)
class CloudCredentials:
    deepgram_key: str = field(repr=False)
    openai_key: str = field(repr=False)
    elevenlabs_key: str = field(repr=False)
    voice_id: str
    voice_owner_consent_verified: bool = field(repr=False)

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
    body = response.json()
    if not isinstance(body, dict) or body.get("status") != "completed":
        raise ValueError("LLM response is not complete")
    try:
        output = body["output"]
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
) -> tuple[str, str | None, bytes | None]:
    """Keep the WAV and generated MP3 in memory; callers decide if they may save them."""
    transcript = transcribe_wav(client, wav, credentials.deepgram_key)
    now = datetime.now(timezone.utc)
    event = ConversationSession().hear(transcript, "DIRECTED", now)
    if event in {"patient_dissent", "closed", "discarded"}:
        return transcript, None, None
    if event in {"auxiliary_alert_candidate", "barge_in_risk_candidate"}:
        reply = "의료진의 도움이 필요한 상황일 수 있어요. 기존 호출 버튼을 이용해주세요."
    elif any(word in transcript for word in ("며칠", "날짜")):
        reply = orientation_date(now)
    elif any(word in transcript for word in ("진단", "처방", "무슨 약", "약을 먹")):
        reply = "의료 판단은 제가 할 수 없어요. 의료진에게 확인해주세요."
    elif any(word in transcript for word in ("너 진짜", "실제 수민", "전화한 거")):
        reply = "나는 실제 가족과 통화하는 사람이 아니라 AI 음성 대화 도우미야."
    else:
        # ponytail: keyword and length guards are an internal-test ceiling; clinical review and measured safety eval precede patients.
        reply = generate_short_reply(client, transcript, known_fact, credentials.openai_key)
    audio = synthesize_mp3(client, reply, credentials)
    return transcript, reply, audio
