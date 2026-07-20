from fastapi import FastAPI

app = FastAPI(title="도담 AI 분석 서버", version="0.1.0")


@app.get("/health")
def health():
    """서버가 살아 있는지 확인하는 엔드포인트."""
    return {"status": "ok"}

@app.post("/analyze/drawing")
def analyze_drawing():
    """그림 분석을 수행하는 엔드포인트."""
    # 그림 분석 로직은 여기해서 수행
    return {
        "status": "ok",
        "objects": [{"label": "집", "confidence": 0.9}],
        "description": "집과 나무가 보이는 그림이에요"
    }
