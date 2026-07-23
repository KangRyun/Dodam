# AI 음성 STT/TTS 내부 요청·응답 계약

> Jira: `S15P11B209-289`, `S15P11B209-179`
> 상태: **확정** (2026-07-23 KST)
> 범위: Spring Boot와 FastAPI AI 서버 사이의 음성 변환(STT)·합성(TTS) 내부 계약

기존 공개 초안 `/stt`·`/tts`는 제공하지 않는다. 아동 음성 원본·인식 텍스트·내부 토큰·저장 key·절대 경로는 로그나 오류·공개 응답에 포함하지 않는다.

## STT — 음성→텍스트

### 요청

```text
POST {AI_BASE_URL}/internal/ai/v1/speech/stt
Content-Type: multipart/form-data
X-Internal-Token: <AI_INTERNAL_TOKEN>
X-Request-Id: <UUID>
```

| 파트 | 규칙 |
| --- | --- |
| `file` | 필수 음성 파일. 288이 검증·저장한 파일만 전송한다. |

- Spring과 FastAPI는 같은 `AI_INTERNAL_TOKEN` 환경변수로 토큰을 검증한다.
- `X-Request-Id`는 필수이며 같은 호출의 재시도에 동일한 값을 사용한다.
- 289는 저장된 파일을 읽기 전용으로 전송하며 업로드·삭제를 재수행하지 않는다.

### 성공 응답 — 200

```json
{
  "text": "...",
  "confidence": null,
  "modelName": "whisper-1",
  "processingTimeMs": 0
}
```

`confidence`는 whisper-1이 제공하지 않아 `null`이며, Spring은 `conversation_messages.stt_confidence DECIMAL(5,4) NULL`에 그대로 저장한다. `text`는 `stt_text`에만 저장하고 로그에 남기지 않는다.

### 오류 응답

| HTTP | 본문 | Spring 처리 |
| --- | --- | --- |
| 401 | `{ "errorCode": "INVALID_INTERNAL_TOKEN" }` | 재시도 없이 `FAILED` |
| 422 | `{ "errorCode": "INVALID_REQUEST" }` | 재시도 없이 `FAILED` |
| 502 | `{ "errorCode": "AI_UPSTREAM_ERROR" }` | 동일 `X-Request-Id`로 1회 재시도 후 `FAILED` |

연결 실패는 1회만 재시도한다. read timeout과 schema 오류는 재전송하지 않고 `FAILED`로 끝낸다. Spring timeout은 connect 2초, read 90초다.

## TTS — 텍스트→음성

```text
POST {AI_BASE_URL}/internal/ai/v1/speech/synthesis
Content-Type: application/json
X-Internal-Token: <AI_INTERNAL_TOKEN>
```

요청은 필수 `text`와 선택 `voice`를 사용한다. 성공 응답은 `audioBase64`, `audioFormat`(`mp3`), `voice`, `modelName`, `processingTimeMs`를 포함한다. 캐릭터 말투 정책은 AI 서버 소유이며 계약으로 노출하지 않는다.

## 저장·상태 전이

```text
PENDING → PROCESSING → SUCCESS | FAILED
```

- 동일 `conversationMessageId`는 조건부 `PENDING → PROCESSING` 갱신으로 선점한다.
- 이미 `PROCESSING`, `SUCCESS`, `FAILED`인 행은 STT를 자동 재호출하지 않는다.
- 성공 시 `stt_text`, `stt_confidence`, `speech_status=SUCCESS`를 저장한다.
- 실패 시 `stt_text`, `stt_confidence`를 `NULL`, `speech_status=FAILED`로 저장한다.

## 제공자 보안 경계

- FastAPI는 canonical 내부 경로만 제공한다.
- 업로드 파일은 `NamedTemporaryFile`로만 처리하고 요청 종료 시 handle을 닫는다.
- GMS 실패는 `502 AI_UPSTREAM_ERROR`로만 반환하며 원문·파일명·토큰·경로를 반환하거나 기록하지 않는다.
