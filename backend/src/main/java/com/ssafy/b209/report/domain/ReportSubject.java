package com.ssafy.b209.report.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;

/**
 * HTP 주제(집·나무·사람) 하나의 관찰 묶음이다 (875 §5 / S15P11B209-960).
 *
 * <p>875 §5 는 이 자리를 "리포트 상세의 스냅샷을 우선 사용(별도 재조립 금지)"으로 규정한다. 그래서 관찰 서술·문답을 생성 시점에 이 테이블로 굳힌다 — 조회할
 * 때마다 대화 로그를 다시 훑으면 같은 리포트가 시점마다 다르게 읽힌다.
 *
 * <p><strong>{@code imageUrl}을 문자열로 담지 않는다.</strong> 그림 조회 URL 은 자산 식별자로 그때그때 발급하는 값이라({@code
 * DrawingAssetFileUrlFactory}) 문자열로 굳히면 인증 경로가 바뀔 때 죽은 링크가 남는다. 대신 주제별 그림 활동 세션을 담아 두고 조회 시점에 상세
 * 화면과 같은 규칙으로 자산을 찾는다.
 *
 * <p>{@code displayOrder}는 {@code HOUSE → TREE → PERSON} 순서를 보존한다. 계약이 순서를 보장하므로 순서가 곧 계약이다.
 */
@Entity
@Table(name = "report_subjects")
public class ReportSubject {

  private static final Set<String> ALLOWED_SUBJECTS = Set.of("HOUSE", "TREE", "PERSON");

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "subject_type", length = 10)
  private String subjectType;

  @Column(name = "drawing_session_id")
  private Long drawingSessionId;

  @OneToMany(
      mappedBy = "subject",
      cascade = CascadeType.ALL,
      orphanRemoval = true,
      fetch = FetchType.LAZY)
  @OrderBy("displayOrder ASC")
  private List<ReportSubjectObservation> observations = new ArrayList<>();

  @OneToMany(
      mappedBy = "subject",
      cascade = CascadeType.ALL,
      orphanRemoval = true,
      fetch = FetchType.LAZY)
  @OrderBy("displayOrder ASC")
  private List<ReportSubjectQaPair> qaPairs = new ArrayList<>();

  @OneToMany(
      mappedBy = "subject",
      cascade = CascadeType.ALL,
      orphanRemoval = true,
      fetch = FetchType.LAZY)
  @OrderBy("displayOrder ASC")
  private List<ReportSubjectInterpretation> interpretations = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportSubject() {}

  private ReportSubject(
      Report report, int displayOrder, String subjectType, Long drawingSessionId) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.subjectType = normalizeSubject(subjectType);
    this.drawingSessionId = drawingSessionId;
  }

  /**
   * 리포트에 연결되는 주제별 관찰 묶음을 생성한다.
   *
   * @param report 묶음이 속한 리포트
   * @param displayOrder 0부터 시작하는 노출 순서이며 {@code HOUSE → TREE → PERSON}을 보존한다
   * @param subjectType HTP 주제({@code HOUSE|TREE|PERSON})이며 주제가 나뉘지 않는 활동은 {@code null}
   * @param drawingSessionId 이 주제의 그림 활동 세션이며 없으면 {@code null}
   * @return 저장 가능한 주제별 관찰 묶음
   * @throws IllegalArgumentException 순서가 음수인 경우
   */
  public static ReportSubject create(
      Report report, int displayOrder, String subjectType, Long drawingSessionId) {
    return new ReportSubject(report, displayOrder, subjectType, drawingSessionId);
  }

  /**
   * 눈으로 확인된 관찰 서술 한 줄을 덧붙인다.
   *
   * @param text 관찰 사실 문장
   */
  public void addObservation(String text) {
    observations.add(ReportSubjectObservation.create(this, observations.size(), text));
  }

  /**
   * 이 주제에서 나눈 문답 한 쌍을 덧붙인다.
   *
   * @param questionText 질문 원문
   * @param answerText 답변 원문이며 건너뛰었으면 {@code null}
   * @param answerState 답변 상태({@code ANSWERED}·{@code SKIPPED})
   * @param inputType 입력 방식({@code TEXT}·{@code VOICE})
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 답변인지 여부
   * @param representative 대표 문답인지 여부
   */
  public void addQaPair(
      String questionText,
      String answerText,
      String answerState,
      String inputType,
      boolean sttNeedsConfirmation,
      boolean representative) {
    qaPairs.add(
        ReportSubjectQaPair.create(
            this,
            qaPairs.size(),
            questionText,
            answerText,
            answerState,
            inputType,
            sttNeedsConfirmation,
            representative));
  }

  /**
   * 이 주제의 관찰이 근거가 된 경향 해석 카드를 연결한다.
   *
   * <p>같은 카드를 두 번 연결하지 않는다 — 응답의 {@code interpretationRefs}에 같은 인덱스가 두 번 실린다.
   *
   * @param interpretation 연결할 경향 해석 카드
   */
  public void referenceInterpretation(ReportPublicInterpretation interpretation) {
    Objects.requireNonNull(interpretation, "interpretation must not be null");
    boolean duplicated =
        interpretations.stream().anyMatch(link -> link.getInterpretation() == interpretation);
    if (duplicated) {
      return;
    }
    interpretations.add(
        ReportSubjectInterpretation.create(this, interpretations.size(), interpretation));
  }

  /**
   * @return 주제별 관찰 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return HTP 주제이며 주제가 나뉘지 않는 활동은 {@code null}
   */
  public String getSubjectType() {
    return subjectType;
  }

  /**
   * @return 이 주제의 그림 활동 세션 식별자이며 없으면 {@code null}
   */
  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  /**
   * @return 노출 순서대로 정렬된 관찰 서술 목록
   */
  public List<ReportSubjectObservation> getObservations() {
    return observations;
  }

  /**
   * @return 노출 순서대로 정렬된 문답 목록
   */
  public List<ReportSubjectQaPair> getQaPairs() {
    return qaPairs;
  }

  /**
   * @return 노출 순서대로 정렬된 경향 해석 참조 목록
   */
  public List<ReportSubjectInterpretation> getInterpretations() {
    return interpretations;
  }

  /**
   * 주제 값을 정규화한다.
   *
   * <p>AI 가 보낸 값이 HTP 주제가 아니면 주제 없음으로 취급한다({@code null}). 알 수 없는 주제를 그대로 저장하면 DB CHECK 위반으로 리포트 저장
   * 전체가 실패하는데, 주제 한 건 때문에 리포트를 죽이는 것은 과하다 — {@link ReportDrawnItem}과 같은 판단이다.
   */
  private static String normalizeSubject(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    String normalized = value.trim().toUpperCase(Locale.ROOT);
    return ALLOWED_SUBJECTS.contains(normalized) ? normalized : null;
  }
}
