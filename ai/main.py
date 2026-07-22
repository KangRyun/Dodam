"""도담 AI 분석 서버 — 처리 흐름 배선.

흐름:  아동 발화 STT(E) → 대화 LLM(F: 그림분석+발화→질문) → 질문 TTS(G) → (대화 루프)

배선(엔드포인트 호출)은 이강륜(173). F의 프롬프트 '내용'·칩 생성과 그림분석 모델은 편주희.
대화 루프(G→E 반복)·재시도는 183(별도) + 루프 위치는 BE 합의 필요.

⚠️ 요청/응답 계약은 '초안' — BE와 합의 후 확정. 원본 음성·발화는 저장·로그하지 않는다(가드레일).
"""

import base64
import tempfile

from fastapi import FastAPI, File, UploadFile
from pydantic import BaseModel

import config
import llm_client
import stt_client
import tts_client

app = FastAPI(title="도담 AI 분석 서버", version="0.1.0")


@app.get("/health")
def health():
    """서버가 살아 있는지 확인."""
    return {"status": "ok"}


# ── 그림분석 / 리포트: 아직 mock (편주희 모델 연결 전) ─────────────
@app.post("/analyze/drawing")
def analyze_drawing():
    """그림 이미지 분석 → 오브젝트/설명. (mock)"""
    return {
        "status": "ok",
        "objects": [{"label": "집", "confidence": 0.9}],
        "description": "집과 나무가 보이는 그림이에요",
    }


# ── E. 아동 발화 STT — whisper-1 (real) ──────────────────────────
@app.post("/stt")
async def stt(file: UploadFile = File(...)):
    """음성 파일 → 텍스트. (원본 음성은 임시파일로만 다루고 저장·로그 안 함)"""
    ext = ""
    if file.filename and "." in file.filename:
        ext = "." + file.filename.rsplit(".", 1)[-1]
    with tempfile.NamedTemporaryFile(suffix=ext or ".mp3") as tmp:
        tmp.write(await file.read())
        tmp.flush()
        text = stt_client.transcribe(tmp.name)
    return {
        "status": "ok",
        "text": text,
        "confidence": None,  # whisper-1은 단순 신뢰도 미제공(스키마 유지용 null)
        "model_id": config.STT_MODEL,
        "pipeline_version": config.PIPELINE_VERSION,
    }


# ── F. 대화 LLM — gpt-4o-mini (real, 프롬프트는 placeholder) ──────
class ConversationRequest(BaseModel):
    utterance: str                       # STT로 받은 아이 발화
    drawing_analysis: str | None = None  # 그림분석 결과(있으면 맥락으로)


@app.post("/analyze/conversation")
def analyze_conversation(req: ConversationRequest):
    """아이 발화(+그림분석) → 캐릭터 다음 질문."""
    # TODO(편주희): 실제 시스템 프롬프트 / 질문·선택칩 생성 규칙(ai/prompts/). 아래는 배선용 placeholder.
    system = (
        "너는 아이와 대화하는 따뜻한 곰돌이야. 아이 말과 그림을 보고 "
        "쉽고 짧은 다음 질문 하나만 해줘."
    )
    context = f"[그림분석] {req.drawing_analysis}\n" if req.drawing_analysis else ""
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": f"{context}[아이 말] {req.utterance}"},
    ]
    question = llm_client.chat(messages)
    return {
        "status": "ok",
        "question": question,
        "chips": [],  # 선택칩 생성은 편주희 프롬프트 영역
        "model_id": config.LLM_MODEL,
        "prompt_version": "placeholder-0",
        "pipeline_version": config.PIPELINE_VERSION,
    }


# ── G. 질문/답변 TTS — gpt-4o-mini-tts (real) ────────────────────
class TtsRequest(BaseModel):
    text: str
    voice: str | None = None


@app.post("/tts")
def tts(req: TtsRequest):
    """텍스트 → 음성(mp3, base64)."""
    audio = tts_client.synthesize(req.text, voice=req.voice)
    return {
        "status": "ok",
        "audio_url": None,
        "audio_base64": base64.b64encode(audio).decode(),
        "duration_sec": None,
        "model_id": config.TTS_MODEL,
        "pipeline_version": config.PIPELINE_VERSION,
    }


@app.post("/analyze/report")
def analyze_report():
    """그림 + 대화 + 감정 종합 → 관찰 리포트. (mock)"""
    return {
        "status": "ok",
        "observations": [
            "집을 화면 가운데에 크게 그렸어요.",
            "따뜻한 색을 주로 사용했어요.",
        ],
        "key_dialogues": [
            {"speaker": "child", "text": "여기는 우리 집이야."},
            {"speaker": "bear", "text": "누구랑 같이 살아?"},
        ],
        "check_points": [
            "가족을 그릴 때 어떤 이야기를 나눴는지 함께 이야기해 보세요.",
        ],
        "disclaimer": "이 리포트는 의학적 진단이 아니라 아이를 이해하기 위한 관찰 참고 자료예요. 걱정되는 점이 있다면 전문가와 상담해 주세요.",
    }
