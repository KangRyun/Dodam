from fastapi import FastAPI

app = FastAPI(title="도담 AI 분석 서버", version="0.1.0")


@app.get("/health")
def health():
    """서버가 살아 있는지 확인하는 엔드포인트."""
    return {"status": "ok"}


@app.post("/analyze/drawing")
def analyze_drawing():
    """그림 이미지 분석 → 오브젝트/설명."""
    return {
        "status": "ok",
        "objects": [{"label": "집", "confidence": 0.9}],
        "description": "집과 나무가 보이는 그림이에요",
    }


@app.post("/analyze/conversation")
def analyze_conversation():
    """아이 발화 → 캐릭터 다음 질문 + 선택 칩."""
    return {
        "status": "ok",
        "question": "이 집에는 누가 살아?",
        "chips": ["엄마", "아빠", "나", "강아지"],
    }


@app.post("/stt")
def stt():
    """음성 → 텍스트."""
    return {
        "status": "ok",
        "text": "빵에에요~",
        "confidence": 0.8,
    }


@app.post("/tts")
def tts():
    """텍스트 → 음성."""
    return {
        "status": "ok",
        "audio_url": "https://example.com/mock-audio.mp3",
        "audio_base64": "",
        "duration_sec": 2.5,
    }


@app.post("/analyze/report")
def analyze_report():
    """그림 + 대화 + 감정 종합 → 관찰 리포트."""
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
