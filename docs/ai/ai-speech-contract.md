# AI 음성 STT/TTS 내부 요청·응답 계약

> Jira: `S15P11B209-289`, `S15P11B209-179`
> **정본: `docs/api/API_명세서_최종.md`** (S15P11B209-400)
> 상태: 운영 중 (as-built, 2026-07-23 확정) — 정본 §19.1과 경로 차이 있음
> 범위: Spring Boot와 FastAPI AI 서버 사이의 음성 변환(STT)·합성(TTS) 내부 계약

## ⚠️ 정본과의 차이

계약의 정본은 `API_명세서_최종.md`다. 이 문서는 **현재 운영 중인 as-built 계약**을 기술하며, 정본 §19.1과 경로·헤더가 다르다.

경로·헤더뿐 아니라 **본문 스키마도 상당히 다르다.** 전환 시 단순 경로 교체로는 끝나지 않는다.

### STT (정본 §19.1 · §19.6)

| 항목 | 이 문서(운영 중) | 정본 |
| --- | --- | --- |
| 경로 | `POST /internal/ai/v1/speech/stt` | `POST /internal/v1/speech/stt` |
| 인증 헤더 | `X-Internal-Token` | `X-Internal-Api-Key` |
| 요청 파트 | `file` 하나 + `X-Request-Id` Header | `audio` + `metadata` JSON(`requestId`, `language=ko-KR`, `ageGroup`, `maxDurationMs`) |
| 응답 | `text`, `confidence`, `modelName`, `processingTimeMs` | `status`, `text`, `confidence`, `language`, `segments[]`, `needsConfirmation`, `modelVersion`, `processingTimeMs` |
| 실패 표현 | HTTP 401/422/502 + `errorCode` | 본문 `status=FAILED` + `failureReason`(`NO_SPEECH`\|`LOW_CONFIDENCE`\|`UNSUPPORTED_AUDIO`\|`TIMEOUT`) |

정본은 `needsConfirmation`과 `failureReason`을 요구한다. 이는 §25 계약 테스트의 "STT low confidence → 추정 텍스트 확정 금지, 폴백 선택지 제공"을 구현하기 위한 필드로, 아동 발화를 임의로 확정하지 않기 위한 가드레일이다. 현행 계약에는 이에 대응하는 필드가 없다.

### TTS (정본 §19.1 · §19.7)

| 항목 | 이 문서(운영 중) | 정본 |
| --- | --- | --- |
| 경로 | `POST /internal/ai/v1/speech/synthesis` | `POST /internal/v1/speech/tts` |
| 요청 | `text`, `voice` | `text`, `voice`, `speed`, `format` |
| 응답 | **JSON** — `audioBase64`, `audioFormat`, `voice`, `modelName`, `processingTimeMs` | **`audio/mpeg` 바이너리** + `X-Audio-Duration-Ms`·`X-TTS-Model-Version` Header |

응답 형식이 base64 JSON ↔ 바이너리로 근본적으로 다르다. 어느 쪽이 나은지는 별도 판단이 필요하다(바이너리는 전송량이 약 25% 적고, base64 JSON은 BE 중계·캐싱 코드가 단순하다).

### 전환 방침

STT는 배포된 BE(`RestClientAiSttClient`)가 경로를 하드코딩해 호출 중이라 바꾸면 즉시 실패한다. TTS는 아직 BE 소비자(S15P11B209-299)가 착수 전이라 여유가 있다 — **TTS를 먼저 정본에 맞추고 STT를 나중에 옮기는 순서**가 위험이 적다.

정합화는 BE·AI 동시 수정이 필요한 2단계 작업이며, 정본 §21이 허용한 방식(새 경로 추가 → BE 전환 확인 → 구 경로 제거)으로 진행한다. 인증 헤더는 이미 AI 서버가 두 헤더를 함께 수용하도록 바뀌어 있다(S15P11B209-398).

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

### `voice` 허용 값 (2026-07-27 추가)

AI 서버가 받는 값은 **서비스 voice 코드**이며, GMS provider voice id로의 변환은 AI가 담당한다(`ai/tts_client.py`의 `SERVICE_VOICE_TO_PROVIDER`). 대소문자는 구분하지 않는다.

| 서비스 코드 | 실제 목소리 |
| --- | --- |
| `CHILD_FRIENDLY_01` | fable (기본 곰돌이 톤) |
| `FABLE` | fable |
| `ALLOY` | alloy |
| `NOVA` | nova |
| `CORAL` | coral |

- **모르는 코드는 거절하지 않고 서버 기본값(`TTS_VOICE`, 기본 `fable`)으로 대체한다.** 목소리 코드 하나 때문에 아이와의 대화에서 음성이 아예 나오지 않는 것을 피하기 위한 선택이며, 대체 시 AI 로그에 경고를 남긴다.
- 이 규칙 이전에는 받은 값을 GMS에 그대로 넘겨, 명세 예시 값(`CHILD_FRIENDLY_01`)을 포함한 모든 대문자 코드가 `BadRequestError` → 502로 실패했다(2026-07-27 실측).
- `speed`는 이 운영 계약의 요청 필드가 **아니다**. 정본 §19.7에는 있으나 아직 반영되지 않았으므로 보내도 무시된다.

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
