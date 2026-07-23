# AI 음성 STT 내부 요청·응답 계약

> Jira: `S15P11B209-289`, `S15P11B209-179`
> 상태: **확정** (2026-07-23 KST)
> 소비자: Spring `RestClientAiSttClient` / 제공자: FastAPI `internal_speech_stt`

아동 음성 원본, STT text, 내부 토큰, 저장 key 및 절대 경로는 로그·오류 응답·공개 응답에 포함하지 않는다.

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

- `X-Internal-Token`은 Spring과 FastAPI가 같은 `AI_INTERNAL_TOKEN` 환경변수로 검증한다.
- `X-Request-Id`는 필수이며 같은 호출의 재시도에 동일한 값을 사용한다.
- Spring은 업로드 단계에서 파일 크기 20MiB와 길이 60초를 검증한다. 289는 저장된 파일을 읽기 전용으로 전송하며 업로드·삭제를 재수행하지 않는다.

### 성공 응답 — 200

```json
{
  "text": "...",
  "confidence": null,
  "modelName": "whisper-1",
  "processingTimeMs": 0
}
```

| 필드 | 규칙 |
| --- | --- |
| `text` | 인식된 텍스트. Spring은 `conversation_messages.stt_text`에만 저장하고 로그에 남기지 않는다. |
| `confidence` | whisper-1이 제공하지 않으므로 항상 `null`. DB `stt_confidence DECIMAL(5,4) NULL`에 그대로 저장한다. |
| `modelName` | 비어 있지 않은 모델명. 현재 `whisper-1`. |
| `processingTimeMs` | 0 이상의 정수. 관측용이며 DB에 영속하지 않는다. |

### 오류 응답

| HTTP | 본문 | Spring 처리 |
| --- | --- | --- |
| 401 | `{ "errorCode": "INVALID_INTERNAL_TOKEN" }` | 재시도 없이 `FAILED` |
| 422 | `{ "errorCode": "INVALID_REQUEST" }` | 재시도 없이 `FAILED`; 입력 값은 응답에 echo하지 않는다. |
| 502 | `{ "errorCode": "AI_UPSTREAM_ERROR" }` | 동일 `X-Request-Id`로 1회만 재시도 후 `FAILED` |

- 연결 실패도 1회만 재시도한다.
- read timeout, schema 오류 및 그 밖의 오류는 재전송하지 않고 `FAILED`로 끝낸다.
- Spring timeout은 connect 2초, read 90초다.

## 저장·상태 전이

```text
PENDING → PROCESSING → SUCCESS | FAILED
```

- 동일 `conversationMessageId`는 조건부 `PENDING → PROCESSING` 갱신으로 선점한다.
- 이미 `PROCESSING`, `SUCCESS`, `FAILED`인 행은 AI를 자동 재호출하지 않는다.
- 성공 시 `stt_text`, `stt_confidence`, `speech_status=SUCCESS`를 저장한다.
- 실패 시 `stt_text`, `stt_confidence`를 `NULL`, `speech_status=FAILED`로 저장한다.

## 제공자 보안 경계

- FastAPI는 canonical 내부 경로만 제공한다. 레거시 공개 `/stt`는 제공하지 않는다.
- FastAPI는 업로드 파일을 `NamedTemporaryFile`로만 처리하고 요청 종료 시 파일 handle을 닫는다.
- GMS 호출 실패는 오류 유형만 `502 AI_UPSTREAM_ERROR`로 반환하며 원문·파일명·토큰·경로를 반환하거나 기록하지 않는다.
