# AI 음성 STT/TTS 내부 요청·응답 계약 (제안)

> Jira: `S15P11B209-179`
> 상태: **제안(2026-07-23)** — BE 소비자(`-289` STT 처리기 · `-299` 질문 TTS)가 미착수 상태에서 AI 쪽이 먼저 제시하는 계약. BE 착수 시 함께 확정하고, 변경은 양쪽 동시 반영한다.
> 범위: Spring Boot와 FastAPI AI 서버 사이의 음성 변환(STT)·합성(TTS) 내부 계약

기존 공개 초안 `/stt`·`/tts`는 **삭제**되었다(A안, 2026-07-23). 근거: nginx `/ai/` 프록시를 통해 무인증으로 인터넷에 노출되던 경로였다(GMS 키 비용 소진 + 아동 음성 경유 경로 공개). `/internal/ai/v1/*`로 이동하면 기존 nginx `/ai/internal/` 외부 차단(404)이 그대로 적용된다.

아동 음성 원문·인식 텍스트·토큰·시크릿은 로그나 오류 응답에 포함하지 않는다.

## 1. STT — 음성→텍스트 변환

- Method/path: `POST /internal/ai/v1/speech/transcription`
- `Content-Type: multipart/form-data` — 파트 이름 **`file`**(음성 파일, mp3/wav/m4a 등)
- `X-Internal-Token`: 필수(`conversations/question`과 동일한 값·검증)

성공 응답(200):

| 필드 | 타입·규칙 |
| --- | --- |
| `text` | 인식된 텍스트(아이 발화). 로그 금지 |
| `confidence` | 항상 `null` — whisper-1이 신뢰도를 제공하지 않음. BE `stt_confidence` 저장 컬럼은 null 허용이어야 한다 |
| `modelName` | 예: `whisper-1` |
| `processingTimeMs` | 0 이상 integer |

## 2. TTS — 텍스트→음성 합성

- Method/path: `POST /internal/ai/v1/speech/synthesis`
- `Content-Type: application/json`
- `X-Internal-Token`: 필수

요청:

| 필드 | 타입·규칙 |
| --- | --- |
| `text` | 필수. 아이에게 들려줄 캐릭터 대사(질문 등) |
| `voice` | 선택. 미지정 시 서버 기본(`fable`) |

성공 응답(200): `audioBase64`(mp3 바이트의 base64) · `audioFormat`(`"mp3"`) · `voice` · `modelName` · `processingTimeMs`

말투(instructions)는 서버가 곰돌이 기본값을 적용하며 계약으로 노출하지 않는다 — 캐릭터 톤 정책은 AI 쪽 소유(프롬프트 담당 편주희).

## 3. 오류 매핑 (두 경로 공통)

| 상태 | 본문 | BE 처리 제안 |
| --- | --- | --- |
| 401 | `{"errorCode": "INVALID_INTERNAL_TOKEN"}` | 설정 오류 — 운영 로그로 원인 확인 |
| 422 | `{"errorCode": "INVALID_REQUEST", "errors": [...]}` — 입력 값 echo 없음 | 요청 결함 — 재시도 무의미 |
| 502 | `{"errorCode": "AI_UPSTREAM_ERROR"}` | GMS 장애 — 재시도 또는 실패 상태 저장(STT `FAILED` 등) |

- 서버 내부 재시도는 하지 않는다(현 구현). BE read timeout 예산과 재시도 정책은 `-289`/`-299` 설계 시 함께 정한다(question 계약의 4s×3회 패턴 참고).
- 오디오/텍스트가 크므로 BE 쪽 timeout은 question(15s)보다 여유가 필요할 수 있다 — 실측 후 결정.

## 4. 가드레일 체크

- 원본 음성은 AI 서버에서 임시파일로만 다루고 저장·로그하지 않는다.
- `text`(아이 발화)·`audioBase64`는 pydantic `repr=False` — 모델 객체가 로그에 찍혀도 원문 비노출.
- 422 응답은 입력 값을 echo하지 않는다(main.py 전역 핸들러).
- 외부 접근: nginx `/ai/internal/` → 404 (경로 존재 자체 은닉).
