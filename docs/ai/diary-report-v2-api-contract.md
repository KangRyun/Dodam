# 그림일기 리포트 V2 API 계약

## 호환 전략

`ObservationGenerationResult` 최상위에 optional `diaryInsights`를 추가한다.

- HTP: `diaryInsights = null`
- 그림일기 근거 충분: 구조화 객체
- 그림일기 근거 부족: `diaryInsights = null`
- 구 소비자: unknown field 무시
- 신 소비자: `diaryInsights`가 있으면 V2 화면, 없으면 레거시 화면

## TypeScript 참고 타입

```ts
export type DiaryRealityStatus = "REAL" | "IMAGINED" | "MIXED" | "UNKNOWN";
export type DiaryTimeScope = "TODAY" | "YESTERDAY" | "RECENT" | "PAST" | "UNKNOWN";

export interface EvidenceSourceRef {
  kind: "QA_ANSWER" | "VLM_OBSERVATION" | "EMOTION_SELECTION" | "ACTIVITY_METRIC";
  id: string;
}

export interface DiaryStorySnapshot {
  headline: string;
  summary: string;
  realityStatus: DiaryRealityStatus;
  timeScope: DiaryTimeScope;
  mainEvent?: string | null;
  evidenceRefs: EvidenceSourceRef[];
}

export type DiaryNarrativeStepType =
  | "EVENT"
  | "CHILD_ACTION"
  | "OTHER_RESPONSE"
  | "EMOTION"
  | "WISH"
  | "OUTCOME";

export interface DiaryNarrativeStep {
  stepType: DiaryNarrativeStepType;
  text: string;
  evidenceRefs: EvidenceSourceRef[];
}

export type DiaryElicitationType =
  | "SPONTANEOUS"
  | "OPEN_INVITATION"
  | "CUED_INVITATION"
  | "FOCUSED_WH"
  | "YES_NO"
  | "MULTIPLE_CHOICE"
  | "CORRECTION"
  | "UNKNOWN";

export interface DiaryChildVoiceItem {
  text: string;
  elicitationType: DiaryElicitationType;
  answerType?: string | null;
  sourceRef?: EvidenceSourceRef | null;
  sttNeedsConfirmation: boolean;
}

export interface DiarySessionObservation {
  observationCode: string;
  title: string;
  description: string;
  scopeText: string;
  evidenceRefs: EvidenceSourceRef[];
}

export interface DiaryCaregiverQuestion {
  question: string;
  purpose: string;
  evidenceRefs: EvidenceSourceRef[];
}

export interface DiaryDataQuality {
  confirmedVoiceCount: number;
  optionAnswerCount: number;
  skippedCount: number;
  sttConfirmationCount: number;
  evidenceCount: number;
  visionSummaryAvailable: boolean;
}

export interface DiaryInsights {
  storySnapshot?: DiaryStorySnapshot | null;
  narrativeFlow: DiaryNarrativeStep[];
  childVoiceItems: DiaryChildVoiceItem[];
  sessionObservations: DiarySessionObservation[];
  caregiverQuestions: DiaryCaregiverQuestion[];
  listeningTip?: string | null;
  dataQuality: DiaryDataQuality;
}
```

## Kotlin/Java DTO 참고

```java
public record DiaryInsights(
    DiaryStorySnapshot storySnapshot,
    List<DiaryNarrativeStep> narrativeFlow,
    List<DiaryChildVoiceItem> childVoiceItems,
    List<DiarySessionObservation> sessionObservations,
    List<DiaryCaregiverQuestion> caregiverQuestions,
    String listeningTip,
    DiaryDataQuality dataQuality
) {}
```

모든 목록은 null 대신 빈 목록으로 정규화하고, 최상위 `diaryInsights`만 nullable로 둔다.

## 저장 권장

### 1차

기존 리포트 JSON 스냅샷에 `diaryInsights` 전체를 함께 저장한다.

### 2차 누적 분석

통계에 필요한 최소 이벤트만 별도 정규화한다.

- activity/session id
- main topic category
- narrative component flags
- emotion expression source
- relationship role
- coping/help-seeking category
- evidence refs

아이·친구 실명은 누적 통계 테이블에 저장하지 않고 관계 역할로 변환한다.

## 화면 표시 주의

- `realityStatus=UNKNOWN`이면 현실 여부 태그 숨김
- `timeScope=UNKNOWN`이면 시점 태그 숨김
- `MULTIPLE_CHOICE`는 `선택지에서 고름`으로 표시
- `dataQuality`는 품질 점수로 환산하지 않음
- `evidenceRefs` ID는 보호자 화면에 노출하지 않음
