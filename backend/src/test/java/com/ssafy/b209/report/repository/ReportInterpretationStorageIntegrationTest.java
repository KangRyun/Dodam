package com.ssafy.b209.report.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportEvidenceItem;
import com.ssafy.b209.report.domain.ReportEvidenceSourceKind;
import com.ssafy.b209.report.domain.ReportEvidenceSourceRef;
import com.ssafy.b209.report.domain.ReportEvidenceSourceType;
import com.ssafy.b209.report.domain.ReportInterpretationCategory;
import com.ssafy.b209.report.domain.ReportInterpretationConfidence;
import com.ssafy.b209.report.domain.ReportInterpretationDisclosureState;
import com.ssafy.b209.report.domain.ReportParentGuide;
import com.ssafy.b209.report.domain.ReportParentGuideType;
import com.ssafy.b209.report.domain.ReportPublicInterpretation;
import com.ssafy.b209.support.IntegrationTestSupport;
import jakarta.persistence.EntityManager;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * V37 경향 해석 저장 구조를 실 MySQL 로 검증한다 (S15P11B209-900).
 *
 * <p>단위 테스트로는 못 잡는 것을 본다: 엔티티 매핑이 실제 DDL 과 맞는지, 리포트 삭제 시 CASCADE 로 카드·근거·연결이 함께 지워지는지, CHECK 제약이
 * 잘못된 상태값·반쪽 참조·잘못된 순서를 막는지, 카드↔근거 FK 가 존재하지 않는 근거 참조를 막는지, 리포트 안 근거 번호 UNIQUE 가 중복을 막는지.
 *
 * <p>특히 <strong>경향 해석이 기존 {@code report_observed_features} 와 다른 테이블에 저장되는지</strong>를 확인한다. 같은 경로에
 * 실으면 {@code resolveVisibility()} 가 전부 EXPERT_ONLY 로 강등해 보호자 화면이 비는데, 그 실패는 기존 부정형 테스트로는 드러나지
 * 않는다(계약 §4-2).
 */
class ReportInterpretationStorageIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_USER_ID = 61L;
  private static final long CHILD_ID = 61L;
  private static final long SESSION_ID = 610L;
  private static final long ANALYSIS_ID = 611L;
  private static final long REPORT_ID = 612L;

  @Autowired private ReportPublicInterpretationRepository interpretationRepository;
  @Autowired private ReportEvidenceItemRepository evidenceItemRepository;
  @Autowired private ReportParentGuideRepository parentGuideRepository;
  @Autowired private ReportRepository reportRepository;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private EntityManager entityManager;

  private Report report;

  @BeforeEach
  void setUpFixture() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'interpretation-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2019-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (61, 'HOUSE', '집', 'GENERAL', 'BOTH', TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, idempotency_key) "
            + "VALUES (?, ?, 61, 'CANVAS', 'COMPLETED', 'COMPLETED', "
            + "'2026-08-05 01:00:00', 'interpretation-key')",
        SESSION_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, analysis_type, idempotency_key, analysis_status, "
            + "requested_at) VALUES (?, ?, 'FINAL', 'interpretation-analysis', 'SUCCESS', "
            + "'2026-08-05 01:30:00')",
        ANALYSIS_ID,
        SESSION_ID);
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "limitations_text) VALUES (?, ?, ?, 1, 'COMPLETED', '참고용 자료입니다.')",
        REPORT_ID,
        SESSION_ID,
        ANALYSIS_ID);
    report = reportRepository.findById(REPORT_ID).orElseThrow();
  }

  @Test
  @Transactional
  void savesInterpretationWithEvidenceThroughRealSchema() {
    ReportEvidenceItem houseAnswer = saveOriginal(1, ReportEvidenceSourceType.CHILD_ANSWER, "202");
    ReportEvidenceItem personAnswer = saveOriginal(2, ReportEvidenceSourceType.CHILD_ANSWER, "203");

    ReportPublicInterpretation card = newCard(0);
    card.referenceEvidence(houseAnswer);
    card.referenceEvidence(personAnswer);
    card.publish();
    interpretationRepository.saveAndFlush(card);
    // 영속성 컨텍스트를 비워 실제 DB 에서 다시 읽는다 — 매핑이 DDL 과 맞는지 보려면 재적재가 필요하다.
    entityManager.clear();

    ReportPublicInterpretation found =
        interpretationRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID).getFirst();
    assertThat(found.getCategory()).isEqualTo(ReportInterpretationCategory.RELATIONSHIP);
    assertThat(found.getDisclosureState()).isEqualTo(ReportInterpretationDisclosureState.PUBLISHED);
    assertThat(found.getWithheldReasonCode()).isNull();
    assertThat(found.getEvidences()).hasSize(2);
    assertThat(found.getEvidences().getFirst().getEvidenceItem().getEvidenceNumber()).isEqualTo(1);
  }

  @Test
  @Transactional
  void storesConfidenceGradeAndAllowsCardsWithoutOne() {
    // V43. 등급 컬럼은 NULL 을 허용해야 한다 — 이 마이그레이션 이전에 저장된 카드에는 등급이 없고,
    //   AI 가 등급을 싣지 않아도 카드는 저장돼야 한다(S15P11B209-982, 836 재발 방지).
    ReportEvidenceItem answer = saveOriginal(1, ReportEvidenceSourceType.CHILD_ANSWER, "202");
    ReportPublicInterpretation graded = newCard(0, ReportInterpretationConfidence.WEAK);
    graded.referenceEvidence(answer);
    ReportPublicInterpretation ungraded = newCard(1, null);
    interpretationRepository.saveAllAndFlush(List.of(graded, ungraded));
    // 영속성 컨텍스트를 비워 실제 DB 에서 다시 읽는다 — 등급이 컬럼에 실제로 내려갔는지 보려면
    //   재적재해야 한다. 메모리 안의 객체만 확인하면 컬럼이 없어도 통과한다.
    entityManager.clear();

    List<ReportPublicInterpretation> found =
        interpretationRepository.findByReportIdOrderByDisplayOrderAsc(REPORT_ID);
    assertThat(found).hasSize(2);
    assertThat(found.getFirst().getConfidence()).isEqualTo(ReportInterpretationConfidence.WEAK);
    assertThat(found.get(1).getConfidence()).isNull();
    // 숫자가 아니라 enum 이름이 그대로 들어가야 CHECK 제약과 맞는다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT confidence FROM report_public_interpretations "
                    + "WHERE report_id = ? AND display_order = 0",
                String.class,
                REPORT_ID))
        .isEqualTo("WEAK");
  }

  @Test
  void rejectsConfidenceGradeOutsideTheAllowedList() {
    // 등급 이름을 DB 가 직접 막는다. BE 를 우회한 경로로도 알 수 없는 등급이 들어가면 안 된다.
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_public_interpretations "
                        + "(report_id, display_order, category, title, tendency_text, "
                        + "disclosure_state, withheld_reason_code, confidence) "
                        + "VALUES (?, 0, 'RELATIONSHIP', '제목', '경향이 보일 수 있습니다.', "
                        + "'WITHHELD', 'PENDING_VERIFICATION', 'VERY_STRONG')",
                    REPORT_ID))
        .isInstanceOf(DataAccessException.class);
  }

  @Test
  void keepsInterpretationOutOfObservedFeatureTable() {
    ReportEvidenceItem answer = saveOriginal(1, ReportEvidenceSourceType.CHILD_ANSWER, "202");
    ReportPublicInterpretation card = newCard(0);
    card.referenceEvidence(answer);
    card.publish();
    interpretationRepository.saveAndFlush(card);

    // 경향 해석은 기존 관찰 특징 경로를 쓰지 않는다(계약 §4-2 결정 1).
    assertThat(countOf("report_public_interpretations")).isEqualTo(1);
    assertThat(countOf("report_observed_features")).isZero();
  }

  @Test
  @Transactional
  void storesDerivedEvidenceOriginsAsRows() {
    ReportEvidenceItem derived =
        evidenceItemRepository.saveAndFlush(
            ReportEvidenceItem.derived(
                report,
                3,
                ReportEvidenceSourceType.REPEATED_SUBJECT,
                "집과 사람 그림에서 같은 이야기를 했어요.",
                List.of(
                    new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202"),
                    new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "203")),
                false));
    entityManager.clear();

    ReportEvidenceItem found = evidenceItemRepository.findById(derived.getId()).orElseThrow();
    assertThat(found.isDerived()).isTrue();
    assertThat(found.getSourceRef()).isEmpty();
    assertThat(found.getDerivations())
        .extracting(derivation -> derivation.getSourceRef().id())
        .containsExactly("202", "203");
  }

  @Test
  void removesInterpretationTreeWhenReportIsDeleted() {
    ReportEvidenceItem answer = saveOriginal(1, ReportEvidenceSourceType.CHILD_ANSWER, "202");
    ReportPublicInterpretation card = newCard(0);
    card.referenceEvidence(answer);
    card.publish();
    interpretationRepository.saveAndFlush(card);
    parentGuideRepository.saveAndFlush(
        ReportParentGuide.create(
            report, ReportParentGuideType.DAILY_PARENTING, 0, "아이 말을 그대로 되짚어 주세요."));

    jdbcTemplate.update("DELETE FROM reports WHERE id = ?", REPORT_ID);

    assertThat(countOf("report_public_interpretations")).isZero();
    assertThat(countOf("report_evidence_items")).isZero();
    assertThat(countOf("report_interpretation_evidences")).isZero();
    assertThat(countOf("report_parent_guides")).isZero();
  }

  @Test
  void removesDerivationsWhenEvidenceItemIsDeleted() {
    ReportEvidenceItem derived =
        evidenceItemRepository.saveAndFlush(
            ReportEvidenceItem.derived(
                report,
                3,
                ReportEvidenceSourceType.LONGITUDINAL,
                "지난 활동에서도 같은 표현이 있었어요.",
                List.of(new ReportEvidenceSourceRef(ReportEvidenceSourceKind.PRIOR_ACTIVITY, "77")),
                false));
    assertThat(countOf("report_evidence_derivations")).isEqualTo(1);

    jdbcTemplate.update("DELETE FROM report_evidence_items WHERE id = ?", derived.getId());

    assertThat(countOf("report_evidence_derivations")).isZero();
  }

  @Test
  void rejectsDuplicatedEvidenceNumberInSameReport() {
    saveOriginal(1, ReportEvidenceSourceType.CHILD_ANSWER, "202");

    assertThatThrownBy(() -> saveOriginal(1, ReportEvidenceSourceType.VISION, "301"))
        .isInstanceOf(DataAccessException.class);
  }

  @Test
  void rejectsHalfFilledSourceReference() {
    // 원본 참조는 종류와 식별자가 함께 있어야 한다 — 한쪽만 있으면 해석할 수 없는 참조다.
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_evidence_items "
                        + "(report_id, evidence_number, source_type, text, source_ref_kind) "
                        + "VALUES (?, 9, 'CHILD_ANSWER', '근거', 'QA_ANSWER')",
                    REPORT_ID))
        .isInstanceOf(DataAccessException.class)
        .hasMessageContaining("ck_report_evidence_items_source_ref_pair");
  }

  @Test
  void rejectsUnknownDisclosureState() {
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_public_interpretations "
                        + "(report_id, display_order, category, title, tendency_text, "
                        + "disclosure_state, withheld_reason_code) "
                        + "VALUES (?, 0, 'EMOTION', '제목', '경향', 'GUARDIAN_VISIBLE', 'X')",
                    REPORT_ID))
        .isInstanceOf(DataAccessException.class)
        .hasMessageContaining("ck_report_public_interpretations_state");
  }

  @Test
  void requiresReasonCodeWhenNotPublished() {
    // 사유 없는 미공개는 나중에 왜 빠졌는지 추적할 수 없다.
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_public_interpretations "
                        + "(report_id, display_order, category, title, tendency_text, "
                        + "disclosure_state) VALUES (?, 0, 'EMOTION', '제목', '경향', 'WITHHELD')",
                    REPORT_ID))
        .isInstanceOf(DataAccessException.class)
        .hasMessageContaining("ck_report_public_interpretations_withheld_reason");
  }

  @Test
  void rejectsEvidenceReferenceToUnknownEvidenceItem() {
    ReportPublicInterpretation card = interpretationRepository.saveAndFlush(newCard(0));

    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_interpretation_evidences "
                        + "(interpretation_id, evidence_item_id, display_order) VALUES (?, ?, 0)",
                    card.getId(),
                    999_999L))
        .isInstanceOf(DataAccessException.class);
  }

  @Test
  void rejectsUnknownParentGuideType() {
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "INSERT INTO report_parent_guides "
                        + "(report_id, guide_type, display_order, guidance) "
                        + "VALUES (?, 'CRISIS_ALERT', 0, '문장')",
                    REPORT_ID))
        .isInstanceOf(DataAccessException.class)
        .hasMessageContaining("ck_report_parent_guides_type");
  }

  @Test
  void readsParentGuidesGroupedByTypeAndOrder() {
    parentGuideRepository.saveAll(
        List.of(
            ReportParentGuide.create(report, ReportParentGuideType.DAILY_PARENTING, 1, "두 번째 조언"),
            ReportParentGuide.create(report, ReportParentGuideType.DAILY_PARENTING, 0, "첫 번째 조언"),
            ReportParentGuide.create(
                report, ReportParentGuideType.PROFESSIONAL_SUPPORT, 0, "상담 안내")));
    parentGuideRepository.flush();

    assertThat(parentGuideRepository.findByReportIdOrderByGuideTypeAscDisplayOrderAsc(REPORT_ID))
        .extracting(ReportParentGuide::getGuidance)
        .containsExactly("첫 번째 조언", "두 번째 조언", "상담 안내");
  }

  private ReportEvidenceItem saveOriginal(
      int evidenceNumber, ReportEvidenceSourceType sourceType, String sourceRefId) {
    return evidenceItemRepository.saveAndFlush(
        ReportEvidenceItem.original(
            report,
            evidenceNumber,
            sourceType,
            "근거 문장 " + evidenceNumber,
            ReportEvidenceSourceKind.QA_ANSWER,
            sourceRefId,
            false));
  }

  private ReportPublicInterpretation newCard(int displayOrder) {
    return newCard(displayOrder, null);
  }

  private ReportPublicInterpretation newCard(
      int displayOrder, ReportInterpretationConfidence confidence) {
    return ReportPublicInterpretation.create(
        report,
        displayOrder,
        ReportInterpretationCategory.RELATIONSHIP,
        "가족과의 정서적 연결",
        "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.",
        "이번 그림 활동에서 나타난 가능성입니다.",
        "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.",
        confidence);
  }

  private int countOf(String table) {
    Integer count = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class);
    return count == null ? 0 : count;
  }
}
