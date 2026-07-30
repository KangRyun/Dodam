# TTS 제공자 Typecast 전환 가이드

**한줄 요약:** 도담 TTS를 GMS(`gpt-4o-mini-tts`)에서 Typecast(`ssfm-v30`)로 바꿀 때 무엇을 어떤 순서로 고쳐야 하는지, 로컬 실기기 E2E 검증 결과와 함께 정리한 문서다.

- 작성: 2026-07-30
- 관련 이슈: `S15P11B209-743`
- 상태: **로컬 검증 완료 / 서버 미적용.** 이 문서는 조사·검증 결과이며 코드 변경은 포함하지 않는다
- 범위: AI 서버(`ai/`)의 TTS 제공자 교체 + 환경변수·시크릿 배선. **BE/FE 코드 변경 없음**(근거는 2절)

---

## 1. 로컬에서 검증된 것 (2026-07-30)

기존 파이프라인을 건드리지 않고 Typecast를 호출하는 대역 서버를 포트 8001에 세워, BE가 그쪽을 보게 한 뒤(`AI_TTS_MODE=http`, `AI_TTS_BASE_URL=http://localhost:8001`) 실기기 앱에서 소리가 나는 것까지 확인했다.

```
앱 → BE(8080) → 대역 서버(8001) → Typecast API → mp3 → BE 저장 → 앱 스트리밍 재생
```

| 항목 | 측정값 |
|---|---|
| `POST /api/v1/conversation-messages/{id}/tts` | 200, `durationMs=3146` |
| `GET /api/v1/conversation-messages/{id}/audio` | 200, 본문 선두 `ID3`(정상 mp3) |
| Typecast 합성 지연 | 718ms (다른 호출 967ms · 1688ms) |
| mp3 크기 | 126KB / 175KB (한 문장) |
| 사용 목소리 | Azzi `tc_66596206b7bd6e89c3a2c54e` (female / child / Conversational) |
| 모델 | `ssfm-v30` |

BE read-timeout은 30s(`application.yml`의 `AI_TTS_READ_TIMEOUT`)이므로 지연 여유는 충분하다.

검증 시 AI 서버(8000)는 일부러 띄우지 않았다. 질문 생성은 폴백 템플릿으로 대체되고(BE 로그 `AI question call failed ... type=CONNECTION_FAILURE`) 그 폴백 문장을 Typecast가 읽었다 — TTS 경로만 분리해 본 것이다.

---

## 2. BE·FE 변경이 필요 없는 근거

`RestClientAiTtsClient`는 응답에서 `audioBase64`·`audioFormat`만 읽는다(`SynthesisHttpResponse` 레코드). `voice`·`modelName`·`processingTimeMs`는 **읽지도 저장하지도 않는다.** 따라서 모델명이 `gpt-4o-mini-tts` → `ssfm-v30`으로 바뀌어도 BE·DB·FE는 영향이 없다.

단, BE의 응답 검증 조건 네 개는 그대로 만족해야 한다.

1. `audioBase64` 존재·비어있지 않음
2. **`audioFormat`이 `mp3`**(대소문자 무시)
3. base64 디코딩 성공
4. 디코딩 결과 길이 > 0

2번 때문에 Typecast 요청에 `output.audio_format: "mp3"`를 **반드시 명시**해야 한다(3절 참조).

---

## 3. Typecast API 계약

```
POST https://api.typecast.ai/v1/text-to-speech
Header: X-API-KEY: <key>

voice_id  (필수)  "tc_" 내장 목소리 / "uc_" 커스텀
text      (필수)  1~2000자. 과금은 길이 기준
model     (필수)  ssfm-v30(최신 권장) | ssfm-v21(안정)
language  (선택)  ISO 639-3. 한국어 = "kor". 생략 시 자동 감지
prompt    (선택)  감정 지정. { "emotion_type": "smart" } = 문맥 자동
output    (선택)  audio_format: "wav"(기본) | "mp3"
                  volume 0~200 / audio_pitch -12~+12 / audio_tempo 0.5~2.0
seed      (선택)  재현용 uint32

200 = 바이너리 오디오(audio/mpeg). 폴링 없음
400 · 401 · 402(크레딧) · 404 · 422 · 429 · 500 = JSON { "detail": ... }
```

목소리 목록:

```
GET https://api.typecast.ai/v2/voices?model=ssfm-v30&age=child&gender=female
→ voice_id, voice_name, models[].emotions, gender, age, use_cases, voice_type
```

`age=child` 필터로 41개가 조회되며, 그중 `use_cases`에 `Conversational`이 있는 것은 Azzi · Sua · Siwoo · Gunwoo · Harper · Woony · Okji · Booqoo · Eogwool이다. 감정은 모든 목소리가 `normal / happy / sad / angry / toneup / tonedown`을 지원한다.

### 함정 세 개

1. **`audio_format` 기본값이 `wav`다.** 명시하지 않으면 BE가 `INVALID_RESPONSE`로 응답을 버린다(2절 2번 조건).
2. **`instructions`에 해당하는 필드가 없다.** 현재 GMS 경로는 `gpt-4o-mini-tts`의 `instructions`로 곰돌이 톤을 자연어로 지시한다(`ai/tts_client.py`의 `BEAR_INSTRUCTIONS`: "따뜻하고 다정한 곰돌이 / 밝고 부드럽게, 조금 천천히"). Typecast에는 이 개념이 없어 **목소리 선택 + `audio_tempo`/`audio_pitch` + `prompt.emotion_type`으로 대체**해야 한다. **톤 품질 회귀가 발생할 수 있는 지점이며 사람이 들어 판정해야 한다.**
3. **`voice_id`가 불투명 해시**(`tc_...`)다. 현재의 서비스 코드 매핑표(`CHILD_FRIENDLY_01` → `fable`)를 제공자별로 분리해야 한다.

---

## 4. 변경 대상

### 4-1. AI 서버 코드

#### `ai/config.py` — 설정 추가

```python
# 제공자 스위치. 기본은 gms — 켜지 않으면 동작이 완전히 동일하다.
TTS_PROVIDER = os.environ.get("TTS_PROVIDER", "gms")  # gms | typecast

TYPECAST_API_KEY = os.environ.get("TYPECAST_API_KEY", "")
TYPECAST_BASE_URL = os.environ.get("TYPECAST_BASE_URL", "https://api.typecast.ai")
TYPECAST_MODEL = os.environ.get("TYPECAST_MODEL", "ssfm-v30")
TYPECAST_VOICE_ID = os.environ.get("TYPECAST_VOICE_ID", "")   # tc_...
TYPECAST_TIMEOUT_SEC = float(os.environ.get("TYPECAST_TIMEOUT_SEC", "25"))
TYPECAST_TEMPO = float(os.environ.get("TYPECAST_TEMPO", "1.0"))


def require_typecast_key() -> str:
    """require_gms_key와 같은 규약 — 없으면 즉시 명확히 실패시킨다."""
    if not TYPECAST_API_KEY:
        raise RuntimeError("TYPECAST_API_KEY가 비어 있습니다.")
    return TYPECAST_API_KEY
```

`TTS_PROVIDER` 기본값을 `gms`로 두는 이유: 크레딧 소진·429·톤 회귀가 발생했을 때 **환경변수 하나로 즉시 복귀**할 수 있고, 기존 테스트(`ai/test_tts_client.py`)가 그대로 통과한다. 이 스위치가 롤백 수단이다.

#### `ai/typecast_client.py` — 신규

`gms.py`는 OpenAI SDK 클라이언트라 Typecast에 쓸 수 없다. `httpx`로 직접 호출한다(`requirements.txt`에 이미 있어 **추가 의존성 0**).

```python
def synthesize(text: str, *, voice: str | None = None, speed: float | None = None) -> bytes:
    body = {
        "voice_id": resolve_voice_id(voice),
        "text": text[:2000],                    # API 상한
        "model": config.TYPECAST_MODEL,
        "language": "kor",
        "prompt": {"emotion_type": "smart"},
        "output": {
            "audio_format": "mp3",              # 기본이 wav — 반드시 명시
            "audio_tempo": speed or config.TYPECAST_TEMPO,
        },
    }
    try:
        resp = httpx.post(
            f"{config.TYPECAST_BASE_URL}/v1/text-to-speech",
            headers={"X-API-KEY": config.require_typecast_key()},
            json=body,
            timeout=config.TYPECAST_TIMEOUT_SEC,
        )
        resp.raise_for_status()
    except httpx.HTTPError as e:
        logger.error("Typecast TTS 호출 실패: %s", type(e).__name__)  # 키·원문 로그 금지
        raise RuntimeError("음성 합성에 실패했어요(Typecast).") from e
    return resp.content
```

실패를 `RuntimeError`로 감싸야 `main.py`의 502(`AI_UPSTREAM_ERROR`) 매핑이 그대로 동작한다.

#### `ai/tts_client.py` — 제공자 분기

`synthesize()`에서 `config.TTS_PROVIDER`로 갈라주고, voice 매핑표를 제공자별로 둔다.

```python
SERVICE_VOICE_TO_TYPECAST = {
    "CHILD_FRIENDLY_01": "tc_66596206b7bd6e89c3a2c54e",   # Azzi
    ...
}
```

**폴백 규칙은 유지한다** — 모르는 코드는 거절하지 않고 서버 기본 목소리로 대체하고 경고만 남긴다. 계약에 명시된 동작이다(`docs/ai/ai-speech-contract.md`): 목소리 코드 하나 때문에 아이가 음성을 아예 못 듣는 쪽이 더 나쁘다.

#### `ai/main.py` — 응답 메타·health

- 합성 응답의 `voice`·`model_name`을 제공자별 값으로 (BE는 안 읽지만 관측·디버깅용)
- `/health`의 `"tts"` 판정이 현재 **GMS 키 유무만 본다.** Typecast로 전환하면 GMS 키만 있어도 READY로 잘못 보고하므로 제공자별 키 기준으로 바꿔야 한다

#### `ai/test_tts_client.py`

제공자 분기 · `audio_format=mp3` 강제 · 미지 voice 폴백 케이스 추가(httpx mock).

### 4-2. 환경변수·시크릿 배선

| 위치 | 넣을 것 | 비밀 |
|---|---|:---:|
| `.env.example` · `infra/.env.example` | `TTS_PROVIDER` `TYPECAST_MODEL` `TYPECAST_VOICE_ID` `TYPECAST_API_KEY`(빈 값) | 예시만 |
| `infra/docker-compose.yml` (`ai` 서비스 environment) | 위 4개, 키는 `${TYPECAST_API_KEY}`로 `.env`에서만 | 키만 |
| `infra/k8s/base/configmap-app.yaml` | `TTS_PROVIDER` `TYPECAST_MODEL` `TYPECAST_VOICE_ID` | 아니오 |
| `infra/k8s/base/ai.yaml` | `TYPECAST_API_KEY` ← `secretKeyRef: dodam-secrets` | **예** |
| `infra/scripts/sync-secrets.sh` 키 목록 | `TYPECAST_API_KEY` | **예** |
| `exec/포팅매뉴얼.md` | 환경변수 표 · 외부 서비스 표 | — |

### 4-3. 문서 (팀 협의 후)

- `docs/ai/ai-speech-contract.md` — `voice` 허용값 절이 "GMS provider voice id로 변환"을 전제한다. Typecast 매핑으로 갱신 필요
- `docs/출시/Play-데이터안전-선언-초안.md` — 제3자 전송 경로가 `앱→BE→AI→GMS→OpenAI`로 기술돼 있다. Typecast(네오사피엔스)가 경로에 추가되면 **데이터 안전 선언 갱신 대상**이다. 나가는 데이터는 아동 발화가 아니라 캐릭터 질문 텍스트지만, 경로 기술은 사실과 맞아야 한다

---

## 5. 적용 순서

1. AI 서버 코드 변경 + 테스트 추가 (`TTS_PROVIDER` 기본 `gms` → 이 단계에서는 운영 동작 무변화)
2. 목소리·톤 확정 — `GET /v2/voices`로 후보를 뽑아 같은 문장으로 비교. 기존 톤 지침("따뜻하고 다정한 곰돌이, 조금 천천히")과 대조
3. 시크릿 배선 + `TYPECAST_API_KEY`를 `dodam-secrets`에 주입
4. **개발/스테이징에서 `TTS_PROVIDER=typecast`로 먼저 전환**해 앱 실사용 경로 확인
5. 문서(계약·데이터 안전) 갱신 협의
6. 운영 전환 — configmap의 `TTS_PROVIDER`만 `typecast`로

**롤백:** `TTS_PROVIDER=gms`로 되돌리고 pod 재시작. 코드를 되돌릴 필요는 없다.

---

## 6. 확인이 필요한 것 (미확정)

| 항목 | 왜 |
|---|---|
| 요금·크레딧 한도 | 과금이 텍스트 길이 기준이다. 대화 1회당 질문 최대 10개가 합성되므로 사용량 추정이 필요하다. 크레딧 소진 시 402 → BE 502 → 폴백 경로 |
| 429(동시 요청) 정책 | 공개 문서에서 확인되지 않았다. 부하 시 재시도·백오프가 필요할 수 있다 |
| 톤 회귀 여부 | `instructions`가 없어 기존 곰돌이 톤과 차이가 날 수 있다. 사람이 들어 판정 |
| 개인정보 제3자 전송 선언 갱신 | 4-3절 참조 |
| 기존 캐시 처리 | 이미 GMS로 합성된 음성이 DB에 캐시돼 있어 재생 시 그대로 나온다. 전환 후 목소리를 통일하려면 캐시 무효화 정책이 필요하다(현재는 성공 캐시가 있으면 AI를 재호출하지 않는다) |

---

## 7. 부록: 대역 서버로 재현하는 방법

BE는 **코드 수정 없이** 환경변수 두 개로 대역 서버에 붙는다.

```
AI_TTS_MODE=http
AI_TTS_BASE_URL=http://localhost:8001
```

대역 서버는 `POST /internal/ai/v1/speech/synthesis`를 받아 `{audioBase64, audioFormat:"mp3", voice, modelName, processingTimeMs}`를 돌려주면 된다(`docs/ai/ai-speech-contract.md`의 TTS 절과 동일).

### 재현 시 걸렸던 함정

1. **Spring RestClient는 요청 본문을 chunked transfer-encoding으로 보낸다.** `Content-Length`가 없어서, 직접 만든 대역 서버가 본문을 빈 것으로 읽고 400을 반환했고 BE는 그것을 502 `TTS_FAILED`로 바꿔 앱에 내려보냈다. 대역 서버를 만들 때 dechunk 처리가 필요하다. 정식 AI 서버(FastAPI)는 자동 처리하므로 이 함정은 대역 서버 한정이다.
2. **로컬 BE는 http라서 Android 평문 차단에 막힌다.** 실기기·에뮬레이터로 로컬 BE를 붙일 때 debug 빌드에만 `usesCleartextTraffic="true"`가 필요하다(운영 manifest에는 넣지 않는다).
3. **`adb reverse`는 앱을 재설치하면 끊긴다.** 앱은 이를 "인터넷 연결이 불안정해요"로 표시해 로그인 실패처럼 보이지만 원인은 포워딩이다.
