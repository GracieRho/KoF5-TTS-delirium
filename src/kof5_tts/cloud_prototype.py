"""Phase-0 hosted speech pipeline for synthetic, consented test material only."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from io import BytesIO
from re import findall, fullmatch, search
from typing import Callable, Sequence
from urllib.parse import quote
import wave

import httpx

from kof5_tts.companion import ConversationSession, UNVERIFIED_SCHEDULE_REPLY, policy_reply


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


def validate_short_wav(wav: bytes) -> float:
    """Reject invalid or long audio before it can reach a hosted provider."""
    if len(wav) > 2_000_000 or wav[:4] != b"RIFF" or wav[8:12] != b"WAVE":
        raise ValueError("expected a short WAV under 2 MB")
    try:
        with wave.open(BytesIO(wav), "rb") as audio:
            frames = audio.getnframes()
            channels = audio.getnchannels()
            width = audio.getsampwidth()
            rate = audio.getframerate()
            if not (frames and channels in (1, 2) and width == 2 and
                    8_000 <= rate <= 48_000 and frames <= rate * 30):
                raise ValueError("expected PCM16 WAV of at most 30 seconds")
            if len(audio.readframes(frames)) != frames * channels * width:
                raise ValueError("WAV audio data is incomplete")
            return frames / rate
    except (EOFError, RuntimeError, wave.Error) as exc:
        raise ValueError("invalid WAV container") from exc


def transcribe_wav(client: httpx.Client, wav: bytes, key: str) -> str:
    """Deepgram Nova-3 batch STT; streaming is a later, measured step."""
    validate_short_wav(wav)
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
    # ponytail: synthetic keyword block may reject benign reassurance; replace only after measured clinical safety evaluation.
    if any(phrase in text for phrase in (
        "나 진짜 수민", "내가 수민이야", "밖에서 전화", "실제로 전화", "약을 복용",
        "약 먹어", "진단은", "처방", "의료진에게 알렸", "의료진에게 전달했",
        "약은", "약이", "약을", "복용", "진단", "수술", "치료", "증상",
        "독감", "폐렴", "감염", "통증", "확실해", "확실합니다",
        "문제없", "안전해", "안전합니다",
    )):
        raise ValueError("LLM response violates a hard safety rule")
    # ponytail: lexical claim guard covers the internal single-fact demo; structured claims need a clinical evaluator.
    claims = findall(r"\d{1,4}(?:년|월|일|시|호)?|오늘|내일|어제|곧|다음 주|CT|검사|퇴원|수술|병실|진료|결과", text)
    if any(claim not in known_fact for claim in claims):
        raise ValueError("LLM response adds an unverified fact claim")
    # ponytail: this demo has only historical travel; allow whereabouts after a valid, structured fact exists.
    if search(r"[가-힣A-Za-z0-9]{2,}에\s*(?:있어|있습니다|계셔|계십니다)", text):
        raise ValueError("LLM response adds an unverified current location")
    return text


def hospital_fact_question(transcript: str) -> bool:
    """Route institution questions away from guardian family memories."""
    return search(r"CT|검사|수술|퇴원|병실|병동|간호사|진료|치료|면회|병원\s*이름|어느\s*병원", transcript) is not None


def _unsupported_fact_question(transcript: str, known_fact: str) -> bool:
    """A family fact cannot support hospital claims or an unrelated family question."""
    if hospital_fact_question(transcript):
        return True
    if not search(r"언제|어디|누구|무엇|뭐|몇|왜|좋아하|기억|알려줘", transcript):
        return False
    question_terms = set(findall(r"[가-힣A-Za-z0-9]{2,}", transcript))
    fact_terms = set(findall(r"[가-힣A-Za-z0-9]{2,}", known_fact))
    generic = {"우리", "오늘", "내일", "언제", "어디", "누구", "무엇", "좋아하는", "기억나", "알려줘"}
    return not any(
        not fullmatch(r"\d+(?:년|월|일|시)?", term)
        for term in question_terms & fact_terms - generic
    )


def synthesize_mp3(client: httpx.Client, text: str, credentials: CloudCredentials,
                   on_first_audio: Callable[[], None] | None = None) -> bytes:
    """ElevenLabs Korean-capable IVC voice playback, never enrollment here."""
    if not text.strip() or len(text) > 200:
        raise ValueError("TTS text must be short")
    with client.stream(
        "POST",
        f"https://api.elevenlabs.io/v1/text-to-speech/{quote(credentials.voice_id, safe='')}",
        headers={"xi-api-key": credentials.elevenlabs_key},
        json={"text": text, "model_id": "eleven_multilingual_v2"},
    ) as response:
        response.raise_for_status()
        audio = bytearray()
        for chunk in response.iter_bytes():
            if len(audio) + len(chunk) > 2_000_000:
                raise ValueError("TTS returned oversized audio")
            if chunk and not audio and on_first_audio is not None:
                on_first_audio()
            audio.extend(chunk)
    if not audio:
        raise ValueError("TTS returned no audio")
    return bytes(audio)


@dataclass(frozen=True)
class EnrolledVoice:
    voice_id: str
    requires_verification: bool | None


def validate_test_voice_samples(samples: Sequence[bytes]) -> None:
    if len(samples) != 3:
        raise ValueError("three voice samples are required")
    durations = [validate_short_wav(sample) for sample in samples]
    if any(duration < 20 for duration in durations) or sum(durations) < 60:
        raise ValueError("three 20–30 second voice samples are required")


def enroll_test_voice(
    client: httpx.Client, samples: Sequence[bytes], key: str, own_voice_consent_verified: bool,
    test_name: str,
) -> EnrolledVoice:
    """Create an IVC clone from the internal tester's own three short samples."""
    if not own_voice_consent_verified or not key:
        raise ValueError("own-voice cloning consent and provider key are required")
    if not fullmatch(r"KoF5 internal self-voice test [0-9a-f]{32}", test_name):
        raise ValueError("a unique internal test voice name is required")
    validate_test_voice_samples(samples)
    response = client.post(
        "https://api.elevenlabs.io/v1/voices/add",
        headers={"xi-api-key": key},
        data={"name": test_name},
        files=[("files[]", (f"sample-{index}.wav", sample, "audio/wav"))
               for index, sample in enumerate(samples, start=1)],
    )
    response.raise_for_status()
    body = response.json()
    voice_id = body.get("voice_id") if isinstance(body, dict) else None
    if not isinstance(voice_id, str) or not fullmatch(r"[A-Za-z0-9_-]{1,100}", voice_id):
        raise ValueError("voice clone response has no valid ID")
    verification = body.get("requires_verification")
    return EnrolledVoice(voice_id, verification if isinstance(verification, bool) else None)


def find_test_voice(client: httpx.Client, test_name: str, key: str) -> str | None:
    """Find only the unique pending IVC name after an uncertain create response."""
    if not key or not fullmatch(r"KoF5 internal self-voice test [0-9a-f]{32}", test_name):
        raise ValueError("provider key and pending test name are required")
    page_token = None
    matches = []
    for _ in range(10):
        params = {"search": test_name, "category": "cloned", "page_size": 100,
                  "include_total_count": "false"}
        if page_token:
            params["next_page_token"] = page_token
        response = client.get("https://api.elevenlabs.io/v2/voices",
                              headers={"xi-api-key": key}, params=params)
        response.raise_for_status()
        body = response.json()
        if not isinstance(body, dict) or not isinstance(body.get("voices"), list):
            raise ValueError("voice list response is invalid")
        for voice in body["voices"]:
            if isinstance(voice, dict) and voice.get("name") == test_name:
                voice_id = voice.get("voice_id")
                if not isinstance(voice_id, str) or not fullmatch(r"[A-Za-z0-9_-]{1,100}", voice_id):
                    raise ValueError("pending voice has an invalid ID")
                matches.append(voice_id)
        if not body.get("has_more"):
            break
        page_token = body.get("next_page_token")
        if not isinstance(page_token, str) or not page_token:
            raise ValueError("voice list pagination is invalid")
    else:
        raise ValueError("voice list pagination exceeded the recovery limit")
    if len(matches) > 1:
        raise ValueError("multiple pending voices require manual reconciliation")
    return matches[0] if matches else None


def delete_test_voice(client: httpx.Client, voice_id: str, key: str) -> None:
    """Remove a task-owned test clone by its provider ID."""
    if not key or not fullmatch(r"[A-Za-z0-9_-]{1,100}", voice_id):
        raise ValueError("provider key and valid test voice ID are required")
    response = client.delete(
        f"https://api.elevenlabs.io/v1/voices/{quote(voice_id, safe='')}",
        headers={"xi-api-key": key},
    )
    response.raise_for_status()
    body = response.json()
    if not isinstance(body, dict) or body.get("status") != "ok":
        raise ValueError("provider did not confirm test voice deletion")


def run_synthetic_pipeline(
    client: httpx.Client, wav: bytes, known_fact: str, credentials: CloudCredentials,
    *, on_first_audio: Callable[[], None] | None = None,
) -> tuple[str, str | None, bytes | None]:
    """Keep the WAV and generated MP3 in memory; callers decide if they may save them."""
    transcript = transcribe_wav(client, wav, credentials.deepgram_key)
    reply, audio = run_synthetic_text_pipeline(
        client, transcript, "DIRECTED", known_fact, credentials,
        on_first_audio=on_first_audio,
    )
    return transcript, reply, audio


def run_synthetic_text_pipeline(
    client: httpx.Client, transcript: str, label: str,
    known_fact: str, credentials: CloudCredentials,
    *, namespace: str = "family_context", on_first_audio: Callable[[], None] | None = None,
) -> tuple[str | None, bytes | None]:
    """Process a bounded iPad transcript without sending candidate audio to hosted STT."""
    if (not transcript.strip() or len(transcript) > 500
            or label not in {"DIRECTED", "AMBIENT", "UNCERTAIN"}
            or namespace not in {"family_context", "hospital_context"}):
        raise ValueError("bounded local transcript and activation label are required")
    now = datetime.now(timezone.utc)
    event = ConversationSession().hear(transcript, label, now)
    if event in {"patient_dissent", "closed", "discarded"}:
        return None, None
    reply = policy_reply(transcript, event, now)
    if namespace == "hospital_context" and reply == UNVERIFIED_SCHEDULE_REPLY:
        reply = None  # A current, approved hospital schedule may answer this default unknown-time reply.
    if reply is None:
        if namespace == "hospital_context":
            # Approved non-medical hospital wording is read unchanged; never let an LLM rewrite a schedule.
            safe_fact = not search(r"약|복용|처방|진단|먹으세요|먹어도|치료하세요|괜찮아|안전합니다", known_fact)
            safe_question = not search(r"결과|진단|치료|약|괜찮아|안전해", transcript)
            reply = known_fact if hospital_fact_question(transcript) and safe_question and 1 <= len(known_fact) <= 200 and safe_fact else \
                "지금 확인된 정보가 없어서 모르겠어. 의료진이나 보호자에게 확인해주세요."
        elif not known_fact.strip() or _unsupported_fact_question(transcript, known_fact):
            reply = "지금 확인된 정보가 없어서 모르겠어. 의료진이나 보호자에게 확인해주세요."
        else:
            # ponytail: lexical grounding is an internal-test ceiling; measured safety eval precedes patients.
            reply = generate_short_reply(client, transcript, known_fact, credentials.openai_key)
    audio = synthesize_mp3(client, reply, credentials, on_first_audio)
    return reply, audio
