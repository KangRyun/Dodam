# 그림일기 리포트 V3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한 회차 그림일기의 원자료, 확인된 사실, 제한적 가설, 다른 설명, 다음 대화와 전체 음성을 근거 추적 가능한 V3 리포트로 제공한다.

**Architecture:** 기존 `diaryInsights` V2를 `schemaVersion=3`으로 확장한다. AI 서버의 결정론적 조립기가 자료 범위와 근거를 검증하고, Backend가 결과와 전체 대화 스냅샷을 정규화해 저장하며, Flutter와 PDF가 동일한 계층을 표시한다.

**Tech Stack:** Python 3.12, Pydantic, unittest, Java 17, Spring Boot 3.5, JPA, Flyway, MySQL 8, JUnit 5, Flutter/Dart, flutter_test

## Global Constraints

- HTP 생성·조회·화면 계약은 수정하지 않는다.
- 기존 V2와 레거시 그림일기는 계속 표시한다.
- JSON DB 컬럼을 추가하지 않는다.
- `LIMITED`에서는 `SESSION_HYPOTHESIS`를 공개하지 않는다.
- `SESSION_HYPOTHESIS`는 최대 두 개이며 근거, 다른 설명, 확인 질문이 모두 필요하다.
- 선택 답변과 예·아니오 답변을 아동의 자발 발화로 계산하지 않는다.
- 음성 URL은 저장하지 않고 조회 시 JWT 인증 Proxy 경로로 만든다.
- 진단명, 심리 점수, 백분위, 또래 비교, 단일 시각 요소의 고정 심리 의미를 출력하지 않는다.
- Java 공개 클래스와 의미가 필요한 공개 메서드에는 실제 책임에 맞는 한국어 Javadoc을 작성한다.
- 작업 브랜치·커밋에는 `S15P11B209-1019`를 사용한다.

---

### Task 1: AI V3 계약과 결정론적 자료 범위

**Files:**
- Modify: `ai/internal_contracts.py:760-930`
- Modify: `ai/diary_report_v2.py:1-1120`
- Modify: `ai/test_diary_report_v2.py`

**Interfaces:**
- Consumes: `ObservationGenerationRequest.subject_summaries`, `selected_emotion_refs`, `behavior_metrics`
- Produces: `DiaryInsights.schema_version`, `DiaryDataScope`, `DiaryStoryComponent`, `DiaryDrawingObservation`

- [x] **Step 1: V3 계약의 실패 테스트를 작성한다**

```python
def test_limited_report_exposes_data_scope_without_session_hypothesis(self):
    request = _diary_request(
        answered_count=1,
        skipped_count=3,
        answer_type="OPTION_ANSWER",
    )
    raw = _signals(
        sessionObservations=[_session_hypothesis()],
        drawingObservations=[_visual_observation()],
    )

    result = diary_report_v2.build_diary_insights(raw, request, vision_available=True)

    self.assertEqual(result.schema_version, 3)
    self.assertEqual(result.data_scope.evidence_level, "LIMITED")
    self.assertEqual(result.session_observations, [])
    self.assertEqual(len(result.drawing_observations), 1)
```

- [x] **Step 2: 실패를 확인한다**

Run: `python -m unittest ai.test_diary_report_v2.DiaryReportV2Test.test_limited_report_exposes_data_scope_without_session_hypothesis -v`

Expected: `DiaryInsights`에 `schema_version` 또는 `data_scope`가 없어 FAIL.

- [x] **Step 3: Pydantic 계약을 추가한다**

```python
class DiaryDataScope(_CamelModel):
    evidence_level: Literal["LIMITED", "PARTIAL", "RICH"]
    summary: str
    confirmed_voice_count: int = 0
    option_answer_count: int = 0
    skipped_count: int = 0
    stt_confirmation_count: int = 0
    visual_observation_count: int = 0


class DiaryStoryComponent(_CamelModel):
    component_type: Literal[
        "ACTOR", "EVENT", "CHILD_ACTION", "EMOTION", "OTHER_RESPONSE", "OUTCOME"
    ]
    status: Literal["CONFIRMED", "VISUAL_ONLY", "SELECTED", "PARTIAL", "UNKNOWN"]
    text: str | None = None
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)


class DiaryDrawingObservation(_CamelModel):
    text: str
    confidence: Literal["HIGH", "MODERATE", "LOW"] = "MODERATE"
    child_confirmed: bool = False
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)
```

`DiaryInsights`에는 `schema_version=3`, `data_scope`, `story_components`, `drawing_observations`를 추가한다.

- [x] **Step 4: 자료 범위 계산기를 구현한다**

```python
def _data_scope(
    req: contracts.ObservationGenerationRequest,
    *,
    visual_observation_count: int,
) -> contracts.DiaryDataScope:
    composed = sum(
        1
        for qa in _iter_qas(req)
        if not qa.stt_needs_confirmation
        and is_spoken_answer(qa.answer_type)
        and _clean_text(qa.answer_text)
    )
    if composed >= 3 and visual_observation_count > 0:
        level = "RICH"
    elif composed > 0:
        level = "PARTIAL"
    else:
        level = "LIMITED"
    return contracts.DiaryDataScope(
        evidence_level=level,
        summary=_DATA_SCOPE_SUMMARIES[level],
        confirmed_voice_count=composed,
        option_answer_count=sum(1 for qa in _iter_qas(req) if is_option_answer(qa.answer_type)),
        skipped_count=req.skipped_count,
        stt_confirmation_count=sum(1 for qa in _iter_qas(req) if qa.stt_needs_confirmation),
        visual_observation_count=visual_observation_count,
    )
```

`LIMITED`이면 조립 단계에서 `SESSION_HYPOTHESIS`를 제거하고, `RICH`여도 가설은 두 개까지만 유지한다.

- [x] **Step 5: 세 자료 범위와 가설 게이트 테스트를 실행한다**

Run: `python -m unittest ai.test_diary_report_v2 -v`

Expected: 모든 V2 기존 테스트와 V3 LIMITED/PARTIAL/RICH 테스트 PASS.

- [x] **Step 6: AI 계약 변경을 커밋한다**

```bash
git add ai/internal_contracts.py ai/diary_report_v2.py ai/test_diary_report_v2.py
git commit -m "[S15P11B209-1019] feat(ai): 그림일기 V3 자료 범위 계약 추가"
```

### Task 2: AI Writer·Reviewer V3 품질 계약

**Files:**
- Modify: `ai/prompts/report_diary.txt`
- Modify: `ai/prompts/report_review_diary.txt`
- Modify: `ai/prompts_registry.py`
- Modify: `ai/report_client.py`
- Modify: `ai/test_diary_report_v2.py`
- Modify: `ai/test_report_client.py`

**Interfaces:**
- Consumes: Task 1의 `DiaryDataScope`, 허용 근거 참조
- Produces: V3 `storyComponents`, `drawingObservations`, 검토 문제 코드

- [x] **Step 1: 품질 코드와 프롬프트 규칙 실패 테스트를 작성한다**

```python
def test_v3_review_prompt_covers_evidence_disclosure_and_alternatives(self):
    text = prompts_registry.load("report_review_diary")
    for code in (
        "GENERIC_INSIGHT",
        "MISSING_ALTERNATIVE_EXPLANATION",
        "EMOTION_LINK_UNCONFIRMED",
        "MISSING_DATA_DISCLOSURE",
        "MISSING_AUDIO_TRANSCRIPT",
        "LONGITUDINAL_OVERCLAIM",
    ):
        self.assertIn(code, text)
```

- [x] **Step 2: 실패를 확인한다**

Run: `python -m unittest ai.test_diary_report_v2.DiaryReportPromptV2Test.test_v3_review_prompt_covers_evidence_disclosure_and_alternatives -v`

Expected: 새 코드가 프롬프트에 없어 FAIL.

- [x] **Step 3: Writer 출력과 Reviewer 규칙을 확장한다**

`report_diary.txt`에 다음 출력을 추가한다.

```json
{
  "storyComponents": [],
  "drawingObservations": [],
  "sessionObservations": []
}
```

다음 규칙을 명시한다.

- 그림 관찰과 해석을 같은 문장에 섞지 않는다.
- 선택 감정과 그림 장면의 관계가 발화로 확인되지 않으면 `UNKNOWN`으로 둔다.
- 직접 발화가 없는 활동에 선호·성향·경향 문장을 만들지 않는다.
- 가설은 두 개 이하이며 `alternativeExplanations`와 `clarificationQuestion`이 필수다.
- 근거가 없으면 빈 배열과 `unknownItems`를 사용한다.

- [x] **Step 4: Reviewer 결과가 해당 섹션만 제거하는 테스트를 추가한다**

```python
def test_missing_alternative_removes_only_hypothesis_card(self):
    payload = _generation_payload_with_v3()
    review = {
        "findings": [
            {
                "target": "diary.observation.0",
                "issue": "MISSING_ALTERNATIVE_EXPLANATION",
                "note": "대안 설명이 없습니다.",
            }
        ]
    }
    result = _generate_with(payload, review)
    self.assertEqual(result.diary_insights.session_observations, [])
    self.assertIsNotNone(result.diary_insights.story_snapshot)
```

- [x] **Step 5: AI 전체 관련 테스트를 실행한다**

Run: `python -m unittest ai.test_diary_report_v2 ai.test_report_client ai.test_report_safety -v`

Expected: PASS.

- [x] **Step 6: 프롬프트 버전을 올리고 커밋한다**

`report_diary`는 `4.0.0`, `report_review_diary`는 `2.0.0`으로 올린다.

```bash
git add ai/prompts/report_diary.txt ai/prompts/report_review_diary.txt ai/prompts_registry.py ai/report_client.py ai/test_diary_report_v2.py ai/test_report_client.py
git commit -m "[S15P11B209-1019] feat(ai): 그림일기 V3 작성 및 검토 규칙 적용"
```

### Task 3: Backend V3 정규화 저장

**Files:**
- Create: `backend/src/main/resources/db/migration/V53__add_diary_report_v3.sql`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/ReportDiaryStoryComponent.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/ReportDiaryVisualObservation.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/domain/ReportDiaryTranscriptEntry.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/service/DiaryTranscriptSnapshotFactory.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/repository/ReportDiaryStoryComponentRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/repository/ReportDiaryVisualObservationRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/report/repository/ReportDiaryTranscriptEntryRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/report/domain/ReportDiaryInsight.java`
- Modify: `backend/src/main/java/com/ssafy/b209/report/dto/ObservationGenerationResult.java:555-800`
- Modify: `backend/src/main/java/com/ssafy/b209/report/service/ObservationReportPersistenceService.java:1371-1585`
- Modify: `backend/src/test/java/com/ssafy/b209/report/service/ObservationReportPersistenceServiceTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/report/service/DiaryTranscriptSnapshotFactoryTest.java`

**Interfaces:**
- Consumes: AI `DiaryInsightsDraft` V3 필드
- Produces: 정규화된 V3 리포트 스냅샷

- [x] **Step 1: 저장 왕복 실패 테스트를 작성한다**

```java
@Test
void persistsV3ScopeStoryComponentsAndVisualObservations() {
  ObservationGenerationResult result = fixture.v3Result("LIMITED");

  service.persist(context, result);

  ReportDiaryInsight insight = diaryInsightRepository.findById(reportId).orElseThrow();
  assertThat(insight.getSchemaVersion()).isEqualTo(3);
  assertThat(insight.getEvidenceLevel()).isEqualTo("LIMITED");
  assertThat(storyComponentRepository.findByReportIdOrderByDisplayOrderAsc(reportId)).hasSize(6);
  assertThat(visualObservationRepository.findByReportIdOrderByDisplayOrderAsc(reportId)).hasSize(2);
}
```

- [x] **Step 2: 실패를 확인한다**

Run: `cd backend && ./gradlew test --tests "com.ssafy.b209.report.service.ObservationReportPersistenceServiceTest"`

Windows: `cd backend; .\gradlew.bat test --tests "com.ssafy.b209.report.service.ObservationReportPersistenceServiceTest"`

Expected: V3 Entity·Repository가 없어 컴파일 FAIL.

- [x] **Step 3: V53 마이그레이션을 작성한다**

```sql
ALTER TABLE report_diary_insights
    ADD COLUMN schema_version SMALLINT NOT NULL DEFAULT 2 COMMENT '그림일기 구조 버전',
    ADD COLUMN evidence_level VARCHAR(20) NULL COMMENT 'LIMITED·PARTIAL·RICH',
    ADD COLUMN data_scope_summary VARCHAR(300) NULL COMMENT '자료 범위 설명',
    ADD COLUMN visual_observation_count SMALLINT NOT NULL DEFAULT 0 COMMENT '그림 관찰 건수';

CREATE TABLE report_diary_story_components (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    component_type VARCHAR(30) NOT NULL,
    confirmation_status VARCHAR(20) NOT NULL,
    text TEXT NULL,
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_story_component (report_id, component_type),
    CONSTRAINT fk_report_diary_story_component_report
      FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
);
```

```sql
CREATE TABLE report_diary_visual_observations (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    text TEXT NOT NULL,
    confidence VARCHAR(20) NOT NULL,
    child_confirmed TINYINT(1) NOT NULL DEFAULT 0,
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_visual_observation_order (report_id, display_order),
    CONSTRAINT fk_report_diary_visual_observation_report
      FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_visual_observation_confidence
      CHECK (confidence IN ('HIGH', 'MODERATE', 'LOW'))
);

CREATE TABLE report_diary_transcript_entries (
    id BIGINT NOT NULL AUTO_INCREMENT,
    report_id BIGINT NOT NULL,
    question_message_id BIGINT NULL,
    answer_message_id BIGINT NULL,
    question_text TEXT NOT NULL,
    answer_text TEXT NULL,
    response_type VARCHAR(20) NOT NULL,
    stt_status VARCHAR(30) NULL,
    audio_duration_ms INT NULL,
    elicitation_type VARCHAR(30) NOT NULL,
    occurred_at DATETIME(6) NOT NULL,
    display_order SMALLINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_report_diary_transcript_order (report_id, display_order),
    CONSTRAINT fk_report_diary_transcript_report
      FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT ck_report_diary_transcript_response_type
      CHECK (response_type IN ('VOICE', 'OPTION', 'TEXT', 'SKIPPED', 'CORRECTION')),
    CONSTRAINT ck_report_diary_transcript_audio_duration
      CHECK (audio_duration_ms IS NULL OR audio_duration_ms >= 0)
);
```

transcript에는 URL이나 JWT를 저장하지 않고 메시지 ID와 텍스트·상태 스냅샷만 저장한다.

- [x] **Step 4: Entity와 Repository를 구현한다**

```java
public static ReportDiaryStoryComponent create(
    Report report,
    String componentType,
    String confirmationStatus,
    String text,
    int displayOrder) {
  return new ReportDiaryStoryComponent(
      Objects.requireNonNull(report),
      componentType,
      confirmationStatus,
      text,
      displayOrder);
}
```

각 공개 Entity와 생성 메서드에는 책임·관계·nullable 의미를 설명하는 한국어 Javadoc을 작성한다.

`DiaryTranscriptSnapshotFactory`는 다음 경계를 제공한다.

```java
List<ReportDiaryTranscriptEntry> create(
    Report report,
    ObservationGenerationContext context)
```

선택 답변은 `OPTION`, 건너뜀은 `SKIPPED`, 확인된 음성 답변은 `VOICE`로 저장한다. 답변 원문은 리포트 생성 시점 값으로 보존하고 Storage URL은 저장하지 않는다.

- [x] **Step 5: `saveDiaryInsights`에 V3 저장을 연결한다**

V2 필드 저장을 유지한 채 `schemaVersion >= 3`일 때 이야기 구성 요소와 그림 관찰을 저장한다. 가설은 `LIMITED`에서 저장하지 않고, 대안 설명과 질문이 없는 `SESSION_HYPOTHESIS`도 저장하지 않는다.

- [x] **Step 6: 저장·마이그레이션 테스트를 실행한다**

Run: `cd backend; .\gradlew.bat test --tests "com.ssafy.b209.report.service.ObservationReportPersistenceServiceTest" --tests "com.ssafy.b209.report.service.DiaryTranscriptSnapshotFactoryTest" --tests "com.ssafy.b209.DatabaseMigrationIntegrationTest"`

Expected: PASS, JSON 타입 컬럼 0개.

- [x] **Step 7: Backend 저장 변경을 커밋한다**

```bash
git add backend/src/main/resources/db/migration/V53__add_diary_report_v3.sql backend/src/main/java/com/ssafy/b209/report backend/src/test/java/com/ssafy/b209/report/service/ObservationReportPersistenceServiceTest.java
git commit -m "[S15P11B209-1019] feat(be): 그림일기 V3 결과 정규화 저장"
```

### Task 4: Backend 전체 대화·음성 조회 계약

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/report/dto/ReportDiaryInsightsResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/report/domain/ReportMessageConfirmationView.java`
- Modify: `backend/src/main/java/com/ssafy/b209/report/service/ReportDetailQueryService.java:900-1010`
- Modify: `backend/src/test/java/com/ssafy/b209/report/service/ReportDetailQueryServiceTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/report/dto/ReportDetailResponseJsonTest.java`

**Interfaces:**
- Consumes: V3 정규화 행과 기존 Conversation Message·음성 Storage 참조
- Produces: `DiaryTranscriptEntryResponse`와 JWT Proxy `audioUrl`

- [x] **Step 1: V3 JSON 계약 실패 테스트를 작성한다**

```java
@Test
void serializesVoiceTranscriptWithStableProxyUrl() throws Exception {
  ReportDetailResponse response = fixture.v3VoiceReport();

  String json = objectMapper.writeValueAsString(response);

  assertThatJson(json)
      .inPath("diaryInsights.transcript[0].answerMessageId").isEqualTo(22);
  assertThatJson(json)
      .inPath("diaryInsights.transcript[0].audioUrl")
      .isEqualTo("/api/v1/conversation-messages/22/audio");
  assertThatJson(json)
      .inPath("diaryInsights.transcript[0].audioAvailable").isEqualTo(true);
}
```

- [x] **Step 2: 실패를 확인한다**

Run: `cd backend; .\gradlew.bat test --tests "com.ssafy.b209.report.dto.ReportDetailResponseJsonTest"`

Expected: `transcript` 필드가 없어 FAIL.

- [x] **Step 3: 응답 DTO를 추가한다**

```java
public record DiaryTranscriptEntryResponse(
    Long questionMessageId,
    Long answerMessageId,
    String questionText,
    String answerText,
    String responseType,
    String sttStatus,
    Integer audioDurationMs,
    boolean audioAvailable,
    String audioUrl,
    String elicitationType,
    OffsetDateTime createdAt) {}
```

`ReportDiaryInsightsResponse`에는 `schemaVersion`, `dataScope`, `storyComponents`, `drawingObservations`, `transcript`를 추가한다. 모든 공개 record와 필드는 실제 nullable·보안 의미를 설명하는 한국어 Javadoc을 갖는다.

- [x] **Step 4: 조회 조립을 구현한다**

- DB 스냅샷 순서로 전체 transcript를 반환한다.
- `answerMessageId`가 있고 음성 Storage 참조가 유효할 때만 `audioAvailable=true`와 Proxy URL을 만든다.
- 삭제된 음성은 텍스트와 상태를 유지하고 URL만 비운다.
- V2 행은 `schemaVersion=2`, V3 목록은 빈 목록으로 반환한다.

- [x] **Step 5: 조회·권한·삭제 음성 테스트를 실행한다**

Run: `cd backend; .\gradlew.bat test --tests "com.ssafy.b209.report.service.ReportDetailQueryServiceTest" --tests "com.ssafy.b209.report.dto.ReportDetailResponseJsonTest" --tests "com.ssafy.b209.report.controller.ReportDetailControllerTest"`

Expected: PASS.

- [x] **Step 6: Backend 조회 계약을 커밋한다**

```bash
git add backend/src/main/java/com/ssafy/b209/report backend/src/test/java/com/ssafy/b209/report
git commit -m "[S15P11B209-1019] feat(be): 그림일기 전체 대화와 음성 계약 제공"
```

### Task 5: Flutter V3 리포트 화면

**Files:**
- Modify: `frontend/mobile/lib/features/report/data/dto/diary_insights_dto.dart`
- Create: `frontend/mobile/lib/features/report/presentation/widgets/diary_report_v3.dart`
- Modify: `frontend/mobile/lib/features/report/presentation/screens/report_screen.dart:570-610`
- Modify: `frontend/mobile/test/features/report/diary_report_v2_test.dart`
- Create: `frontend/mobile/test/features/report/diary_report_v3_test.dart`
- Modify: `frontend/mobile/test/features/report/report_screen_test.dart`

**Interfaces:**
- Consumes: Backend `diaryInsights.schemaVersion=3`
- Produces: 자료 범위·정밀 관찰·이야기 지도·가설·전체 대화/음성 V3 UI

- [x] **Step 1: DTO 파싱 실패 테스트를 작성한다**

```dart
test('V3 자료 범위와 전체 음성 대화를 파싱한다', () {
  final dto = DiaryInsightsDto.fromJson(v3Fixture);

  expect(dto.schemaVersion, 3);
  expect(dto.dataScope?.evidenceLevel, 'RICH');
  expect(dto.storyComponents, hasLength(6));
  expect(dto.transcript.single.audioAvailable, isTrue);
  expect(dto.transcript.single.audioUrl,
      '/api/v1/conversation-messages/22/audio');
});
```

- [x] **Step 2: 실패를 확인한다**

Run: `cd frontend/mobile; flutter test test/features/report/diary_report_v3_test.dart`

Expected: V3 DTO가 없어 컴파일 FAIL.

- [x] **Step 3: V3 DTO를 추가한다**

```dart
final class DiaryTranscriptEntryDto {
  const DiaryTranscriptEntryDto({
    required this.responseType,
    required this.audioAvailable,
    this.answerMessageId,
    this.questionText,
    this.answerText,
    this.sttStatus,
    this.audioDurationMs,
    this.audioUrl,
    this.elicitationType,
    this.createdAt,
  });

  final int? answerMessageId;
  final String? questionText, answerText, sttStatus, audioUrl, elicitationType, createdAt;
  final String responseType;
  final int? audioDurationMs;
  final bool audioAvailable;
}
```

V2 파싱 기본값은 `schemaVersion=2`, V3 목록은 빈 목록으로 둔다.

- [x] **Step 4: V3 본문 Widget의 실패 테스트를 작성한다**

```dart
testWidgets('LIMITED 리포트는 자료 범위와 미확인 내용을 표시하고 가설을 숨긴다',
    (tester) async {
  await tester.pumpWidget(reportApp(limitedV3));

  expect(find.text('이번 기록의 자료 범위'), findsOneWidget);
  expect(find.text('이번에는 확인하지 못했어요'), findsOneWidget);
  expect(find.text('그림과 대화에서 생각해 볼 수 있는 가능성'), findsNothing);
});
```

- [x] **Step 5: `DiaryReportV3Body`를 구현한다**

표시 순서는 설계 문서 §8을 그대로 따른다. 음성 버튼은 `audioAvailable && audioUrl != null`일 때만 기존 `VoiceAnswerPlaybackController`를 통해 표시한다. `responseType=OPTION`은 `선택지에서 고름`, `SKIPPED`는 `질문을 건너뜀`으로 구분한다.

- [x] **Step 6: Report Screen 버전 분기를 연결한다**

```dart
if (report.diaryInsights case final insights?) ...[
  if (insights.schemaVersion >= 3)
    DiaryReportV3Body(insights: insights, playbackController: playbackController)
  else
    DiaryReportV2Body(insights: insights, qaPairs: report.allQaPairs),
]
```

- [x] **Step 7: Widget·화면 회귀 테스트를 실행한다**

Run: `cd frontend/mobile; flutter test test/features/report/diary_report_v3_test.dart test/features/report/diary_report_v2_test.dart test/features/report/report_screen_test.dart`

Expected: PASS.

- [x] **Step 8: Flutter V3 화면을 커밋한다**

```bash
git add frontend/mobile/lib/features/report frontend/mobile/test/features/report
git commit -m "[S15P11B209-1019] feat(app): 그림일기 리포트 V3 화면 구현"
```

### Task 6: PDF·문서·종단 검증

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/report/service/ReportPdfTemplate.java`
- Modify: `backend/src/test/java/com/ssafy/b209/report/service/ReportPdfTemplateTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/report/service/ReportPdfRendererProductionShapeTest.java`
- Modify: `docs/ai/diary-report-v2-api-contract.md`
- Modify: `docs/ai/diary-report-v2-ui-spec.md`
- Create: `docs/ai/diary-report-v3-example.json`

**Interfaces:**
- Consumes: 완성된 V3 Report Detail DTO
- Produces: 화면과 같은 근거 계층의 PDF와 최신 계약 문서

- [ ] **Step 1: PDF 실패 테스트를 작성한다**

```java
@Test
void v3PdfContainsEvidenceScopeAndTranscriptWithoutAudioUrl() {
  String html = new ReportPdfTemplate(fixture.v3Report(), fixture.images()).build();

  assertThat(html).contains("이번 기록의 자료 범위");
  assertThat(html).contains("전체 대화");
  assertThat(html).contains("앱에서 음성 재생 가능");
  assertThat(html).doesNotContain("/conversation-messages/22/audio");
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd backend; .\gradlew.bat test --tests "com.ssafy.b209.report.service.ReportPdfTemplateTest"`

Expected: V3 섹션이 없어 FAIL.

- [ ] **Step 3: PDF V3 섹션을 구현한다**

- 화면과 같은 자료 범위·관찰·이야기 구성·가설·미확인·전체 대화 순서를 사용한다.
- 음성 URL과 JWT는 출력하지 않는다.
- 음성이 존재하는 발화에만 `앱에서 음성 재생 가능`을 붙인다.
- 실제 딥링크가 없으므로 QR은 생성하지 않는다.

- [ ] **Step 4: 계약 문서와 예시를 V3로 갱신한다**

기존 V2 호환 규칙을 유지하면서 V3 필드, LIMITED/PARTIAL/RICH 기준, transcript 음성 수명주기, 품질 코드를 문서화한다. 예시는 `LIMITED` 활동으로 작성해 근거가 적을 때도 일반론을 만들지 않는 것을 보여 준다.

- [ ] **Step 5: 전체 검증을 실행한다**

```powershell
python -m unittest discover -s ai -p "test_*.py"
cd backend
.\gradlew.bat clean test
.\gradlew.bat spotlessCheck
.\gradlew.bat javadoc
Test-Path build\docs\javadoc\index.html
cd ..\frontend\mobile
flutter analyze
flutter test
```

Expected:

- Python 테스트 PASS
- Backend 테스트·Spotless·Javadoc PASS
- `build/docs/javadoc/index.html`이 `True`
- Flutter analyze 오류 0개
- Flutter 전체 테스트 PASS

- [ ] **Step 6: 문서와 PDF를 커밋한다**

```bash
git add backend/src/main/java/com/ssafy/b209/report/service/ReportPdfTemplate.java backend/src/test/java/com/ssafy/b209/report/service docs/ai
git commit -m "[S15P11B209-1019] docs(report): 그림일기 V3 계약과 PDF 반영"
```

- [ ] **Step 7: Jira와 MR용 검증 결과를 정리한다**

다음 항목을 `S15P11B209-1019` 댓글과 MR 설명에 기록한다.

- V3 API 필드와 하위 호환 방식
- LIMITED/PARTIAL/RICH Fixture 결과
- 전체 대화·음성 삭제 상태 결과
- AI·Backend·Flutter 명령별 성공 여부
- Javadoc 생성 경로
- 누적 관찰은 `S15P11B209-1020`에서 이어짐
