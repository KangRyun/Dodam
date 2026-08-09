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

export type DiaryConnectionType =
  | "FEELING_SHARING"
  | "COMFORT_SEEKING"
  | "SHARED_JOY"
  | "PERSPECTIVE_TAKING"
  | "GENERAL_CONNECTION";

export interface DiaryCaregiverQuestion {
  question: string;
  purpose: string;
  connectionType: DiaryConnectionType;
  responseGuide?: string | null;
  coRegulationAction?: string | null;
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

## caregiverQuestions — "오늘 마음 나누기" 교감 카드

기존 "이어서 물어보면 좋아요"를 정서적 교감 전용 섹션으로 재설계했다. 부모에게 **무엇을 물을지(`question`)** 와 **아이 답에 어떻게 마음으로 반응할지(`responseGuide`)** 를 함께 준다.

| 필드 | 출처 | 설명 |
|------|------|------|
| `question` | LLM 제안 → 근거 게이트 | 감정 앵커 질문. 감정을 나눌 수 있는 질문 우선 |
| `purpose` | LLM(선택) | 이 질문으로 더 들어볼 내용. 없으면 빈 문자열 |
| `connectionType` | LLM 태그 → **서버 화이트리스트 검증** | 아래 enum |
| `responseGuide` | **서버 정적 매핑**(LLM 아님) | 부모 공감 반응(반영적 경청 — 마음을 그대로 받아 주고 함께 느껴 주기) |
| `coRegulationAction` | **서버 정적 매핑**(선택) | 함께 해보기 한 줄. 없으면 `null` |
| `evidenceRefs` | 근거 검증 | 이 질문이 이어지는 근거. `GENERAL_CONNECTION`은 빈 배열 |

### connectionType enum과 서버 조립 규칙

- 감정 교감 4종: `FEELING_SHARING`(감정 나누기) · `COMFORT_SEEKING`(속상함·위로) · `SHARED_JOY`(기쁨 함께) · `PERSPECTIVE_TAKING`(다른 사람 마음 헤아리기)
- `GENERAL_CONNECTION`(기본 교감 = 빈 상태 폴백, **근거 불필요**)

조립 규칙(AI 서버):

1. LLM이 태그한 `connectionType`을 감정 4종 화이트리스트로 검증한다. 없거나 무효면 **그 카드를 드롭**한다(GENERAL로 덮지 않음).
2. 통과 카드에 `connectionType`으로 정적 `responseGuide`·`coRegulationAction`을 부착한다. **LLM이 준 `responseGuide`·`coRegulationAction`은 무시**한다 — 공감 문구를 모델에게 맡기면 발달 규준 주장·지시형 훈육으로 새기 쉬워서다.
3. 감정 우선으로 정렬한다: `FEELING_SHARING > COMFORT_SEEKING > SHARED_JOY > PERSPECTIVE_TAKING`. 최대 2개.
4. 게이트 통과 0개면 `GENERAL_CONNECTION` 기본 카드 1개(고정 `question`, `responseGuide`, `coRegulationAction=null`, `evidenceRefs=[]`)를 준다.
5. **빈 V2 방어:** 기본 카드는 `diaryInsights` None-guard 통과 후에만 주입한다. guard 판정에는 기본 카드를 세지 않는다 — 다른 실컨텐츠(핵심 이야기·흐름·관찰·발달 맥락)가 하나도 없으면 기본 카드도 만들지 않고 `diaryInsights` 자체가 `null`이다.

정적 `responseGuide`·`coRegulationAction` 문구는 UI 스펙(`diary-report-v2-ui-spec.md`)과 예시 JSON(`diary-report-v2-example.json`)에 그대로 있다. 금지어(`규준`·`또래`·`정상발달`·`지연`·`충족`)를 쓰지 않는다.

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
- `caregiverQuestions`는 "오늘 마음 나누기" 섹션으로 표시하고, `responseGuide`·`coRegulationAction`은 서버 문구를 그대로 노출한다(클라이언트가 생성·요약하지 않음)
- `coRegulationAction`이 `null`이면 그 줄만 숨긴다
