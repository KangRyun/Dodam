package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * 경향 해석 카드의 확신 등급이 AI 응답에서 보호자 응답까지 한 줄로 이어져 있는지 본다 (S15P11B209-982).
 *
 * <p><b>왜 통합 테스트인가:</b> 이 값은 AI 응답 → 어댑터 → 안전 검증기 → Entity → MySQL 컬럼 → 조회 서비스 → 보호자 DTO 라는 <b>일곱
 * 계층</b>을 지난다. 계층마다 단위 테스트를 붙여도 <b>사이의 한 칸이 비어 있으면</b> 전부 통과한다. 902 가 정확히 그랬다 — 저장 메서드를 만들어 놓고
 * {@code complete()} 에서 부르지 않아, 단위 테스트는 전부 초록인 채로 몇 주 동안 보호자 화면이 비어 있었다. 그래서 여기서는 <b>양 끝만</b> 잡는다:
 * AI 가 보낸 문자열을 넣고, 보호자가 받는 응답에서 그 문자열이 나오는지 본다.
 *
 * <p>Mock 을 쓰지 않는다. 실제 MySQL 의 V44 컬럼과 {@code @Enumerated(STRING)} 매핑, 그리고 공개 판정을 통과한 카드만 응답에 싣는 조회
 * 규칙까지 함께 지난다.
 */
class ReportInterpretationConfidenceIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_USER_ID = 82L;
  private static final long CHILD_ID = 82L;
  private static final long DRAWING_TYPE_ID = 82L;
  private static final long SESSION_ID = 820L;
  private static final long ANALYSIS_ID = 821L;
  private static final long REPORT_ID = 822L;

  /** 계약 §3 예시 그대로의 가능성 어조 문장이다 — 어조 검사(1단)를 통과해야 카드가 공개된다. */
  private static final String TENDENCY_TEXT = "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.";

  private static final String SCOPE_TEXT = "이번 그림 활동에서 나타난 가능성입니다.";
  private static final String HOME_GUIDE = "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.";

  /** 어떤 공개 카드도 가리키지 않는 근거의 아이 발화다 — 이 문자열이 응답에 나오면 985 가 재발한 것이다. */
  private static final String ORPHAN_UTTERANCE = "아무 카드도 가리키지 않는 아이 말";

  @Autowired private ObservationReportPersistenceService persistenceService;
  @Autowired private ReportDetailQueryService queryService;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUpFixture() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'confidence-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2019-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    // 보호자 접근 권한이 없으면 조회가 403 으로 끝나 등급까지 가보지도 못한다.
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (?, 'ART_DIARY', '그림일기', 'GENERAL', 'BOTH', TRUE, 1)",
        DRAWING_TYPE_ID);
    // 리포트 생성 직전 상태다. complete() 는 이 세션 상태를 건드리지 않으므로(P0-2) 어떤 값이든
    //   이 검증에는 영향이 없다 — 여기서 보는 것은 경향 해석 카드의 확신 등급뿐이다.
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, idempotency_key) "
            + "VALUES (?, ?, ?, 'CANVAS', 'IN_PROGRESS', 'REPORTING', "
            + "'2026-08-06 01:00:00', 'confidence-key')",
        SESSION_ID,
        CHILD_ID,
        DRAWING_TYPE_ID);
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, analysis_type, idempotency_key, analysis_status, "
            + "requested_at) VALUES (?, ?, 'FINAL', 'confidence-analysis', 'PENDING', "
            + "'2026-08-06 01:30:00')",
        ANALYSIS_ID,
        SESSION_ID);
    // limitations_text 는 NOT NULL 이고 기본값이 없다 — 여기 값은 자리만 채우는 것이고,
    // complete() 가 AI 응답의 한계 고지로 덮어쓴다.
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "is_expert_review_recommended, limitations_text) "
            + "VALUES (?, ?, ?, 1, 'GENERATING', FALSE, '생성 중')",
        REPORT_ID,
        SESSION_ID,
        ANALYSIS_ID);
  }

  @Test
  void carriesConfidenceGradeFromAiPayloadToGuardianResponse() {
    // ★ 이 이슈의 본체다. AI 가 "WEAK" 를 보내면 보호자 응답의 같은 카드에 "WEAK" 가 실려야 한다.
    generateReportWith(cardConfidence("WEAK"));

    ReportPublicInterpretationResponse card = onlyPublishedCard();

    assertThat(card.confidence()).isEqualTo("WEAK");
    // 등급이 다른 필드를 밀어내지 않았는지 함께 본다 — 레코드 컴포넌트를 꼬리에 붙였으므로 순서가 어긋나면
    //   여기서 드러난다.
    assertThat(card.category()).isEqualTo("RELATIONSHIP");
    assertThat(card.tendencyText()).isEqualTo(TENDENCY_TEXT);
    assertThat(card.evidenceRefs()).containsExactly(1, 2);
  }

  @Test
  void keepsCardAndReportWhenAiOmitsConfidence() {
    // 836·837 재발 방지. 등급은 optional 이므로 없어도 리포트는 정상 생성되고 카드도 그대로 나간다.
    //   여기서 예외가 나면 필수 필드로 잘못 모델링했거나 Bean Validation 이 붙은 것이다.
    generateReportWith(cardConfidence(null));

    ReportPublicInterpretationResponse card = onlyPublishedCard();

    assertThat(card.confidence()).isNull();
    assertThat(card.tendencyText()).isEqualTo(TENDENCY_TEXT);
  }

  @Test
  void keepsCardWhenConfidenceGradeIsUnknown() {
    // AI 가 등급 이름을 늘리거나 오타를 내도 카드는 살아야 한다. 등급만 버리고 카드는 그대로 공개한다 —
    //   모르는 값 때문에 카드를 떨어뜨리면 보호자 화면에서 관찰 하나가 통째로 사라진다.
    generateReportWith(cardConfidence("VERY_STRONG"));

    ReportPublicInterpretationResponse card = onlyPublishedCard();

    assertThat(card.confidence()).isNull();
    assertThat(card.title()).isEqualTo("가족과의 정서적 연결");
  }

  @Test
  void doesNotShipEvidenceThatNoPublishedCardReferences() {
    // S15P11B209-985. 근거는 공개 여부와 무관하게 **저장**된다(미공개 사유 추적). 그러나 **응답**에는
    //   공개 카드가 참조하는 것만 실려야 한다. 예전에는 리포트의 근거 행을 전부 실어, 안전 검증기가
    //   내보내지 않기로 한 카드의 근거 — 대개 아이 발화 인용 — 까지 보호자 기기로 전송됐다.
    //   앱이 조회용 맵으로만 써서 화면엔 안 떴지만, 그건 클라이언트 구현에 기댄 방어다.
    generateReportWith(cardWithUnreferencedEvidence());

    ReportDetailResponse response = queryService.getReport(GUARDIAN_USER_ID, REPORT_ID);

    assertThat(response.evidenceItems())
        .as("공개 카드가 참조하는 근거 2건만 실려야 한다")
        .extracting(item -> item.evidenceId())
        .containsExactly(1, 2);
    assertThat(response.evidenceItems())
        .as("어떤 공개 카드도 가리키지 않는 근거의 아이 발화가 응답에 남으면 안 된다")
        .noneMatch(item -> item.text().contains(ORPHAN_UTTERANCE));
    // 거른 뒤에도 카드의 참조가 살아 있어야 한다 — evidenceRefs 와 evidenceId 가 둘 다
    //   evidenceNumber 값이라 목록에서 일부를 빼도 참조가 어긋나지 않는다는 것을 여기서 고정한다.
    assertThat(onlyPublishedCard().evidenceRefs()).containsExactly(1, 2);
  }

  /**
   * 리포트 생성 완료 경로를 실제로 태운다 — 저장 메서드를 직접 부르지 않는 것이 이 테스트의 요점이다.
   *
   * <p>{@code rawJson} 은 null 로 둔다(S15P11B209-983 이 원문 보관을 더하며 시그니처를 바꿨다). 이
   * 테스트가 보는 것은 확신도가 계약에서 보호자 응답까지 실려 가는가이고, 원문 보관은 983 이 자기
   * 테스트로 덮는다.
   */
  private void generateReportWith(ObservationGenerationResult result) {
    ObservationGenerationContext context =
        persistenceService.loadContext(ANALYSIS_ID).orElseThrow();
    persistenceService.complete(context, new ObservationGeneration(result, null));
  }

  /** 보호자 응답에서 공개된 카드 한 건을 꺼낸다. 공개 판정까지 통과했는지도 여기서 함께 확인된다. */
  private ReportPublicInterpretationResponse onlyPublishedCard() {
    ReportDetailResponse response = queryService.getReport(GUARDIAN_USER_ID, REPORT_ID);
    assertThat(response.publicInterpretations())
        .as("구조 게이트·표현 필터를 통과한 카드가 보호자 응답에 실려야 등급을 확인할 수 있다")
        .hasSize(1);
    return response.publicInterpretations().getFirst();
  }

  /**
   * 확신 등급만 바꾼 AI 응답을 만든다.
   *
   * <p>카드는 <b>공개 조건을 충족</b>하도록 짠다: 독립 근거 2건 + 아이 표현 1건 이상(계약 §4-3). 조건을 못 채우면 카드가 미공개로 저장돼 보호자 응답에
   * 실리지 않고, 그러면 등급 검증 자체가 성립하지 않는다.
   *
   * @param confidence AI 가 실은 등급 문자열이며 등급을 싣지 않은 경우를 표현하려면 {@code null}
   */
  /**
   * 공개 카드가 참조하지 않는 근거를 하나 더 실은 AI 응답을 만든다 (S15P11B209-985).
   *
   * <p>3번 근거는 카드의 {@code evidenceRefs}(1, 2)에 없다. 저장은 되지만 보호자 응답에는 실리지 않아야 한다.
   */
  private ObservationGenerationResult cardWithUnreferencedEvidence() {
    ObservationGenerationResult base = cardConfidence("MODERATE");
    List<ObservationGenerationResult.EvidenceItemDraft> withOrphan =
        new java.util.ArrayList<>(base.evidenceItems());
    withOrphan.add(
        new ObservationGenerationResult.EvidenceItemDraft(
            3L,
            "CHILD_ANSWER",
            "\"" + ORPHAN_UTTERANCE + "\" 라고 답했어요.",
            new ObservationGenerationResult.EvidenceSourceRefDraft("QA_ANSWER", "203"),
            List.of(),
            false));
    return new ObservationGenerationResult(
        base.requestId(),
        base.modelName(),
        base.modelVersion(),
        base.confidence(),
        base.observationDraft(),
        base.conversationSummary(),
        base.activityNotes(),
        base.followUpGuides(),
        base.guardianQuestions(),
        base.limitationsText(),
        base.drawnItems(),
        base.publicInterpretations(),
        withOrphan,
        base.parentGuides(),
        base.crisisAlert(),
        base.subjectReports(),
        base.ragReferences());
  }

  private ObservationGenerationResult cardConfidence(String confidence) {
    return new ObservationGenerationResult(
        "confidence-request",
        "gpt-4o-mini",
        "pipeline=0.1.0",
        new BigDecimal("0.80"),
        new ObservationGenerationResult.ObservationDraft(
            "AI_REVIEWED",
            "그림을 편안하게 그렸어요.",
            "색을 다양하게 썼어요.",
            "특별히 주의할 점은 없었어요.",
            "그림과 대화에서 확인했어요.",
            "함께 이야기 나눠 보세요.",
            "오늘 그림에서 가장 마음에 드는 곳은 어디야?",
            false,
            "본 결과는 진단이 아니라 관찰 기록입니다.",
            List.of()),
        new ObservationGenerationResult.ConversationSummaryDraft(
            "가족 이야기를 나눴어요.", "가족", "행복", "SELECTED", "우리 가족이요"),
        List.of(),
        List.of(),
        List.of(),
        "이 리포트는 진단이 아닌 관찰 참고 자료입니다.",
        null,
        List.of(
            new ObservationGenerationResult.PublicInterpretationDraft(
                "RELATIONSHIP",
                "가족과의 정서적 연결",
                TENDENCY_TEXT,
                SCOPE_TEXT,
                HOME_GUIDE,
                List.of(1L, 2L),
                confidence)),
        List.of(
            // 종류가 다른 원본 근거 2건 — 하나는 아이 표현이어야 공개 조건을 채운다.
            new ObservationGenerationResult.EvidenceItemDraft(
                1L,
                "CHILD_ANSWER",
                "\"우리 가족이요\" 라고 답했어요.",
                new ObservationGenerationResult.EvidenceSourceRefDraft("QA_ANSWER", "202"),
                List.of(),
                false),
            new ObservationGenerationResult.EvidenceItemDraft(
                2L,
                "VISION",
                "가족을 화면 가운데에 모아 그렸어요.",
                new ObservationGenerationResult.EvidenceSourceRefDraft("DETECTED_OBJECT", "71"),
                List.of(),
                false)),
        List.of(),
        null);
  }
}
