# AI 음성 STT/TTS 내부 요청·응답 계약

> Jira: `S15P11B209-289`, `S15P11B209-179`, `S15P11B209-744`(무음·실패 상태 처리), `S15P11B209-963`(캐릭터별 TTS 음성)
> **정본: `docs/api/API_명세서_최종.md`** (S15P11B209-400)
> 상태: 운영 중 (as-built, 2026-07-23 확정 · **2026-08-05 STT 실패 상태 필드 추가**) — 정본 §19.1과 경로 차이 있음
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
| 응답 | `text`, `confidence`, `modelName`, `processingTimeMs`, **`status`, `failureReason`, `needsConfirmation`** | `status`, `text`, `confidence`, `language`, `segments[]`, `needsConfirmation`, `modelVersion`, `processingTimeMs` |
| 실패 표현 | 인식 실패는 **본문 `status=FAILED` + `failureReason`**(정본과 같은 어휘). 호출 자체의 실패만 HTTP 401/422/502 + `errorCode` | 본문 `status=FAILED` + `failureReason`(`NO_SPEECH`\|`LOW_CONFIDENCE`\|`UNSUPPORTED_AUDIO`\|`TIMEOUT`) |

정본은 `needsConfirmation`과 `failureReason`을 요구한다. 이는 §25 계약 테스트의 "STT low confidence → 추정 텍스트 확정 금지, 폴백 선택지 제공"을 구현하기 위한 필드로, 아동 발화를 임의로 확정하지 않기 위한 가드레일이다.

**2026-08-05에 이 세 필드를 현행 경로에 추가했다**(아래 "무음·저신뢰 판정" 절). 남은 차이는 경로·인증 헤더·요청 파트 구성과 `language`·`segments[]`·`modelVersion`이며, 응답의 실패 표현은 정본과 같은 어휘를 쓴다.

추가 배경: 필드가 없던 동안 아동이 아무 말도 하지 않은 녹음이 whisper 학습 데이터 정형구("구독, 좋아요, 알림설정 부탁드립니다")로 인식돼 **아동 답변으로 저장되고 다음 질문의 근거가 됐다**(2026-08-05 실측, 대화 337 / messageId 1200). 무음을 무음이라고 말하지 않으면 아이가 하지 않은 말이 기록에 남는다.

### TTS (정본 §19.1 · §19.7)

| 항목 | 이 문서(운영 중) | 정본 |
| --- | --- | --- |
| 경로 | `POST /internal/ai/v1/speech/synthesis` | `POST /internal/v1/speech/tts` |
| 요청 | `text`, `voice` | `text`, `voice`, `speed`, `format` |
| 응답 | **JSON** — `audioBase64`, `audioFormat`, `voice`, `modelName`, `processingTimeMs` | **`audio/mpeg` 바이너리** + `X-Audio-Duration-Ms`·`X-TTS-Model-Version` Header |

응답 형식이 base64 JSON ↔ 바이너리로 근본적으로 다르다. 어느 쪽이 나은지는 별도 판단이 필요하다(바이너리는 전송량이 약 25% 적고, base64 JSON은 BE 중계·캐싱 코드가 단순하다).

### 전환 방침

STT는 배포된 BE(`RestClientAiSttClient`)가 경로를 하드코딩해 호출 중이라 바꾸면 즉시 실패한다. TTS BE 소비자(S15P11B209-299)는 이미 운영 중이다. 경로·응답 형식 정합화는 기존 TTS 캐시·재생 경로와 함께 별도 이슈에서 단계적으로 진행한다.

정합화는 BE·AI 동시 수정이 필요한 2단계 작업이며, 정본 §21이 허용한 방식(새 경로 추가 → BE 전환 확인 → 구 경로 제거)으로 진행한다. 인증 헤더는 이미 AI 서버가 두 헤더를 함께 수용하도록 바뀌어 있다(S15P11B209-398).

2026-08-05에는 **경로를 옮기지 않고 응답 필드만 정본 어휘로 정렬**했다. 실패 표현이 없어 아동 발화가 오염되는 문제를 경로 이전까지 미룰 수 없었고, 필드 추가는 하위 호환이라 배포 순서 제약 없이 먼저 적용할 수 있었기 때문이다. 경로·헤더·요청 파트 이전은 그대로 남은 과제다.

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
  "processingTimeMs": 0,
  "status": "SUCCESS",
  "failureReason": null,
  "needsConfirmation": false
}
```

`confidence`는 whisper-1이 제공하지 않아 `null`이며, Spring은 `conversation_messages.stt_confidence DECIMAL(5,4) NULL`에 그대로 저장한다. `text`는 `stt_text`에만 저장하고 로그에 남기지 않는다.

`status`·`failureReason`·`needsConfirmation`은 2026-08-05에 **덧붙인** 필드다. 기존 4필드를 그대로 두었으므로 배포 순서에 제약이 없다 — 구 Spring은 모르는 필드를 무시하고, 구 AI가 세 필드를 생략하면 Spring이 `SUCCESS`로 간주한 뒤 `text` 공백 여부로 무음을 판정한다.

`confidence`는 계속 `null`이다. whisper `verbose_json`이 주는 `avg_logprob`는 확률이 아니라 로그 확률이므로 0~1로 환산하면 우리가 만들어낸 수치가 DB에 남는다. 불확실성은 수치가 아니라 `needsConfirmation`으로 전달한다.

### 무음·저신뢰 판정 — 200 + `status=FAILED` (2026-08-05)

인식 실패는 추측 문장을 만들지 않고 `text: ""`와 함께 실패 사유를 돌려준다(정본 §19.6·§25).

```json
{
  "text": "",
  "confidence": null,
  "modelName": "whisper-1",
  "processingTimeMs": 0,
  "status": "FAILED",
  "failureReason": "NO_SPEECH",
  "needsConfirmation": false
}
```

`text`는 `null`이 아니라 **빈 문자열**이다. 처음부터 non-null 계약이던 필드의 타입을 바꾸면 구 Spring 파서가 schema 오류로 떨어진다.

| `failureReason` | 판정 근거 |
| --- | --- |
| `NO_SPEECH` | 인식 텍스트가 비었거나, 세그먼트 `no_speech_prob`의 길이 가중 평균이 `STT_NO_SPEECH_PROB_MAX`(기본 0.6) 이상이거나, 전체 발화가 whisper 자막 정형구와 **완전히 일치** |
| `LOW_CONFIDENCE` | `avg_logprob`의 길이 가중 평균이 `STT_AVG_LOGPROB_FAIL_MAX`(기본 -1.0) 미만 |
| `UNSUPPORTED_AUDIO` | `verbose_json`·평문 두 형식 모두 GMS가 400으로 거절 |
| `TIMEOUT` | GMS 호출이 제한 시간 내에 끝나지 않음 |

`STT_AVG_LOGPROB_FAIL_MAX` 이상이면서 `STT_AVG_LOGPROB_CONFIRM_MAX`(기본 -0.6) 미만이면 실패로 만들지 않고 `status=SUCCESS` + `needsConfirmation=true`로 돌려준다 — 텍스트는 쓰되 확정하지 않는다.

판정 순서는 무음이 먼저다. 무음 구간의 신뢰도는 "무엇을 잘못 들었는지"만 말하고, 들을 말이 없었다는 사실이 더 강한 근거이며 아이에게 보여줄 안내(선택지)도 그쪽이 정확하다.

**정형구 목록에 짧은 대답을 넣지 않는다.** `네`·`음`·`안녕하세요`·`감사합니다`는 whisper가 무음에 붙이기도 하지만 아이가 실제로 그렇게 답하는 일이 훨씬 흔하다. 목록으로 지우면 진짜 답변을 삭제하므로, 짧은 발화는 지표로만 판정한다. 매칭은 공백·문장부호를 제거한 **전체 일치**로 한정한다 — 부분 일치를 허용하면 "엄마가 구독 좋아요 누르라고 했어"까지 지운다.

AI는 GMS에 `response_format=verbose_json`으로 먼저 요청하고, 게이트웨이가 그 형식을 거절하면 평문으로 **1회 폴백**한다. 폴백에서는 세그먼트 지표가 없어 빈 텍스트·정형구 규칙만 남는다(기능은 유지되고 판정 강도만 낮아진다). 폴백이 일어나면 AI 로그에 `STT verbose_json 거절 — 평문 응답으로 재시도한다`를 남긴다.

로그에는 사유 코드와 지표만 남기고 **인식 텍스트는 남기지 않는다**.

### 오류 응답

| HTTP | 본문 | Spring 처리 |
| --- | --- | --- |
| 401 | `{ "errorCode": "INVALID_INTERNAL_TOKEN" }` | 재시도 없이 `FAILED` |
| 422 | `{ "errorCode": "INVALID_REQUEST" }` | 재시도 없이 `FAILED` |
| 502 | `{ "errorCode": "AI_UPSTREAM_ERROR" }` | 동일 `X-Request-Id`로 1회 재시도 후 `FAILED` |

연결 실패는 1회만 재시도한다. read timeout과 schema 오류는 재전송하지 않고 `FAILED`로 끝낸다. Spring timeout은 connect 2초, read 90초다.

**HTTP 오류와 인식 실패는 다르다.** 무음·저신뢰·지원하지 않는 오디오·GMS 타임아웃은 상류 장애가 아니라 정상적인 결과이므로 **200 + `status=FAILED`**로 알린다. Spring은 이 응답을 재시도하지 않고 곧바로 `FAILED`로 저장한다. 502는 GMS 자체가 실패한 경우로 한정한다.

Spring은 응답 어휘를 검증한다. 모르는 `status`, 목록 밖의 `failureReason`, `failureReason` 없는 `FAILED`는 `RESPONSE_SCHEMA_INVALID`로 떨어뜨려 `FAILED`로 끝낸다(fail-closed) — 판정할 수 없는 응답을 성공으로 넘기면 AI가 거절한 텍스트가 저장될 수 있다.

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
| `CHILD_FRIENDLY_01` | fable (이전 클라이언트 호환 기본값) |
| `FABLE` | fable (BASE·도담이) |
| `NOVA` | nova (PRINCESS·공주) |
| `ASH` | ash (DINO·공룡) |
| `BALLAD` | ballad (OCTOPUS·문어) |
| `VERSE` | verse (EXPLORER·탐험가) |
| `SAGE` | sage (RIBBON·리본) |
| `ECHO` | echo (PRINCE·왕자) |
| `ALLOY` | alloy |
| `CORAL` | coral |

- **모르는 코드는 거절하지 않고 서버 기본값(`TTS_VOICE`, 기본 `fable`)으로 대체한다.** 목소리 코드 하나 때문에 아이와의 대화에서 음성이 아예 나오지 않는 것을 피하기 위한 선택이며, 대체 시 AI 로그에 경고를 남긴다.
- 이 규칙 이전에는 받은 값을 GMS에 그대로 넘겨, 명세 예시 값(`CHILD_FRIENDLY_01`)을 포함한 모든 대문자 코드가 `BadRequestError` → 502로 실패했다(2026-07-27 실측).
- `speed`는 AI 서버 호출에는 아직 반영되지 않아 보내도 합성 속도는 바뀌지 않는다. 다만 Spring은 공개 API 계약에 따라 `messageId`·`voice`·`speed` 조합으로 캐시를 구분한다.

## 저장·상태 전이

```text
PENDING → PROCESSING → SUCCESS | FAILED
```

- 동일 `conversationMessageId`는 조건부 `PENDING → PROCESSING` 갱신으로 선점한다.
- 이미 `PROCESSING`, `SUCCESS`, `FAILED`인 행은 STT를 자동 재호출하지 않는다.
- 성공 시 `stt_text`, `stt_confidence`, `speech_status=SUCCESS`를 저장한다.
- 실패 시 `stt_text`, `stt_confidence`를 `NULL`, `speech_status=FAILED`로 저장한다.
- **`status=FAILED` 응답과 `text`가 공백인 응답은 `stt_text`를 저장하지 않고 `speech_status=FAILED`로 끝낸다**(2026-08-05). 후자는 상태 필드가 없는 구 AI 응답에 대한 Spring 쪽 독립 방어선이다 — 없으면 두 계층의 배포 사이 구간에 빈 답변이 아동 발화로 기록된다.
- `needsConfirmation=true`면 `needs_guardian_confirmation`을 세운다. 이 값은 기존 값과 **OR**로 합친다 — 한 번 필요해진 확인은 AI가 확신한다고 내려가지 않는다.

### 실패한 음성 답변은 답변으로 세지 않는다 (2026-08-05)

`speech_status=FAILED`인 `VOICE_ANSWER` 행은 중복 답변 판정(`OptionAnswerMessageRepository.existsAnswerForQuestion`)에서 제외한다. 인식이 거절되면 아이 말은 기록에 남지 않고 앱이 같은 질문에 선택지를 띄우는데(정본 §25), 그 행을 답변으로 세면 아이가 선택지를 눌러도 `ANSWER_ALREADY_SUBMITTED`로 막혀 대화가 그 질문에서 끊긴다.

`speech_status`가 `NULL`인 음성 답변은 상태를 알 수 없으므로 **답변으로 센다**. 판정 불가를 "답변 없음"으로 넘기면 같은 질문에 답변이 두 개 생긴다.

## 제공자 보안 경계

- FastAPI는 canonical 내부 경로만 제공한다.
- 업로드 파일은 `NamedTemporaryFile`로만 처리하고 요청 종료 시 handle을 닫는다.
- GMS 실패는 `502 AI_UPSTREAM_ERROR`로만 반환하며 원문·파일명·토큰·경로를 반환하거나 기록하지 않는다.
