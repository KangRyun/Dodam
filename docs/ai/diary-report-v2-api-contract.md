# 그림일기 리포트 V3 API 계약

> 파일명은 기존 링크 호환을 위해 유지한다. 정본 스키마는 `schemaVersion=3`이며 V2 응답도 계속 읽을 수 있다.

## 1. 목적과 경계

V3는 한 회차 그림일기의 원자료 범위, 확인된 사실, 제한적 가설, 다른 설명, 다음 확인 질문과 전체 대화를 근거 순서대로 제공한다. 단일 활동으로 성격·심리 상태·발달 수준을 진단하지 않으며 위험 확률, 백분위와 또래 비교 점수를 만들지 않는다.

외부 선별검사 기록은 기존 `screeningSummary`에만 표시한다. HTP 응답과 생성 흐름은 변경하지 않는다.

## 2. 호환 규칙

- `diaryInsights == null`: HTP 또는 레거시 그림일기 화면
- `schemaVersion` 없음: V2로 간주
- `schemaVersion == 2`: 기존 V2 필드만 사용
- `schemaVersion >= 3`: V3 필드 사용
- 모든 목록은 `null` 대신 빈 목록
- 기존 리포트를 V3처럼 추정해 마이그레이션하지 않음

## 3. V3 확장 필드

기존 `storySnapshot`, `childVoiceItems`, `sessionObservations`, `caregiverQuestions`, `developmentalObservations`, `unknownItems`, `dataQuality`를 유지하고 다음을 추가한다.

```ts
type EvidenceLevel = "LIMITED" | "PARTIAL" | "RICH";
type ConfirmationStatus = "CONFIRMED" | "VISUAL_ONLY" | "UNKNOWN";
type ResponseType = "VOICE" | "OPTION" | "TEXT" | "SKIPPED" | "CORRECTION";

interface DiaryDataScope {
  evidenceLevel: EvidenceLevel;
  summary: string;
  confirmedVoiceCount: number;
  optionAnswerCount: number;
  skippedCount: number;
  sttConfirmationCount: number;
  visualObservationCount: number;
}

interface DiaryStoryComponent {
  componentType:
    | "ACTOR" | "EVENT" | "CHILD_ACTION" | "OTHER_RESPONSE"
    | "EMOTION" | "WISH" | "OUTCOME";
  confirmationStatus: ConfirmationStatus;
  text?: string | null;
  evidenceRefs: EvidenceSourceRef[];
}

interface DiaryDrawingObservation {
  text: string;
  confidence: "HIGH" | "MODERATE" | "LOW";
  childConfirmed: boolean;
  evidenceRefs: EvidenceSourceRef[];
}

interface DiaryTranscriptEntry {
  questionMessageId?: number | null;
  answerMessageId?: number | null;
  questionText?: string | null;
  answerText?: string | null;
  responseType: ResponseType;
  sttStatus?: string | null;
  audioDurationMs?: number | null;
  audioAvailable: boolean;
  audioUrl?: string | null;
  elicitationType?: string | null;
  createdAt?: string | null;
}

interface DiaryInsightsV3 extends DiaryInsightsV2 {
  schemaVersion: 3;
  dataScope: DiaryDataScope;
  storyComponents: DiaryStoryComponent[];
  drawingObservations: DiaryDrawingObservation[];
  transcript: DiaryTranscriptEntry[];
}
```

`EvidenceSourceRef`는 `kind`, `id`만 가진 내부 추적 참조다. 보호자 화면과 PDF에는 식별자를 그대로 표시하지 않는다.

## 4. 자료 충분도

`evidenceLevel`은 아이의 능력 점수가 아니라 이번 리포트가 사용할 수 있었던 자료 범위다.

| 단계 | 기준과 표시 정책 |
|---|---|
| `LIMITED` | 확인 가능한 아동 직접 구성 발화가 없음. 객관적 그림 관찰·선택·미확인·전체 기록만 표시하고 `SESSION_HYPOTHESIS` 금지 |
| `PARTIAL` | 일부 직접 발화가 있으나 사건 흐름이 충분하지 않음. 확인된 표현과 다음 탐색 중심, 독립 근거가 있을 때만 가설 허용 |
| `RICH` | 직접 발화·이야기 흐름·별도 그림 관찰이 충분함. 가설 최대 2개 |

모든 `SESSION_HYPOTHESIS`는 다음 세 가지를 함께 가져야 한다.

1. 이번 활동 한정 가설
2. 하나 이상의 다른 가능한 설명
3. 다음 확인 질문

하나라도 없으면 해당 가설을 저장·표시하지 않는다.

## 5. 전체 대화와 음성 수명주기

- `transcript`는 리포트 생성 시점의 질문·답변 텍스트 스냅샷이다.
- 이후 원본 음성이 삭제돼도 `questionText`, `answerText`, `responseType`, `sttStatus`는 유지한다.
- `audioUrl`은 저장하지 않고 조회 시 현재 Conversation Message의 음성 참조로 만든다.
- 재생 가능한 경우에만 `audioAvailable=true`와 `/api/v1/conversation-messages/{messageId}/audio` 상대 경로를 준다.
- URL은 JWT 인증 Proxy이며 공개 URL이나 presigned URL이 아니다.
- DB 참조가 없어지면 `audioAvailable=false`, `audioUrl=null`이다.
- 실제 Storage 객체가 이미 사라졌으면 재생 API가 404를 반환할 수 있으며 앱은 텍스트를 유지하고 재생 실패만 안내한다.
- PDF에는 음성 URL이나 토큰을 넣지 않고 `앱에서 음성 재생 가능`만 표시한다.

## 6. 품질 검수 코드

다음 문제는 해당 항목만 제거하며, 검수 실패 로그에 아이 발화나 그림 설명 원문을 기록하지 않는다.

- `DUPLICATE_CONTENT`
- `GENERIC_INSIGHT`
- `GENERIC_GUIDANCE`
- `UNSUPPORTED_PREFERENCE`
- `UNSUPPORTED_PSYCHOLOGY`
- `MISSING_ALTERNATIVE_EXPLANATION`
- `ELICITATION_OVERCLAIM`
- `EMOTION_LINK_UNCONFIRMED`
- `MISSING_DATA_DISCLOSURE`
- `CHILD_VOICE_DISTORTION`
- `MISSING_AUDIO_TRANSCRIPT`
- `LONGITUDINAL_OVERCLAIM`

## 7. 저장 원칙

- V3 헤더와 반복 항목은 정규화 테이블에 저장한다.
- 전체 transcript는 대표 발화 제한과 별개로 생성 시점 전체 순서를 보존한다.
- 음성 Storage Key와 URL은 리포트 스냅샷 테이블에 저장하지 않는다.
- 실명은 누적 통계로 전달하지 않고 관계 역할로 변환한다.
- V3 조립 일부가 실패하면 유효한 섹션만 유지하며 전체 실패 시 V2 또는 레거시로 폴백한다.

## 8. 예시

근거가 적어도 일반론을 채우지 않는 LIMITED 예시는 [`diary-report-v3-example.json`](./diary-report-v3-example.json)을 따른다.
