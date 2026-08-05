package com.ssafy.b209.report.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * 경향 해석 카드가 참조하는 근거 한 건이다.
 *
 * <p>근거는 <strong>원본</strong>이거나 <strong>파생</strong>이며 둘 중 하나만 될 수 있다. 원본 근거는 서버가 발급한 참조({@code
 * sourceRef}) 하나를 갖고, 파생 근거는 그 참조 대신 원본 참조 목록({@code derivations})을 갖는다. 이 배타 규칙은 DB CHECK로 표현할 수
 * 없어(행 존재 여부를 검사해야 한다) 이 팩토리에서 강제한다.
 *
 * <p>독립 근거 개수는 근거 종류가 아니라 <strong>말단 원본 참조의 합집합 크기</strong>로 센다. 종류로 세면 같은 답변 하나를 두 종류로 신고해 2건을 만들
 * 수 있고, 반대로 서로 다른 그림의 답변 두 개가 1건으로 깎인다.
 */
@Entity
@Table(name = "report_evidence_items")
public class ReportEvidenceItem {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "evidence_number", nullable = false)
  private int evidenceNumber;

  @Enumerated(EnumType.STRING)
  @Column(name = "source_type", nullable = false, length = 20)
  private ReportEvidenceSourceType sourceType;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Enumerated(EnumType.STRING)
  @Column(name = "source_ref_kind", length = 20)
  private ReportEvidenceSourceKind sourceRefKind;

  @Column(name = "source_ref_id", length = 64)
  private String sourceRefId;

  @Column(name = "stt_needs_confirmation", nullable = false)
  private boolean sttNeedsConfirmation;

  @OneToMany(
      mappedBy = "evidenceItem",
      cascade = CascadeType.ALL,
      orphanRemoval = true,
      fetch = FetchType.LAZY)
  @OrderBy("displayOrder ASC")
  private List<ReportEvidenceDerivation> derivations = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportEvidenceItem() {}

  private ReportEvidenceItem(
      Report report,
      int evidenceNumber,
      ReportEvidenceSourceType sourceType,
      String text,
      boolean sttNeedsConfirmation) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    if (evidenceNumber <= 0) {
      throw new IllegalArgumentException("evidenceNumber must be positive");
    }
    this.evidenceNumber = evidenceNumber;
    this.sourceType = Objects.requireNonNull(sourceType, "sourceType must not be null");
    this.text = requireText(text, "text");
    this.sttNeedsConfirmation = sttNeedsConfirmation;
  }

  /**
   * 서버가 발급한 참조 하나를 갖는 원본 근거를 생성한다.
   *
   * @param report 근거가 속한 리포트
   * @param evidenceNumber 리포트 안에서 유일한 근거 번호(1 이상)이며 응답의 {@code evidenceId}로 나간다
   * @param sourceType 근거 종류이며 파생 종류는 쓸 수 없다
   * @param text 근거 문장
   * @param sourceRefKind 원본 참조의 종류
   * @param sourceRefId 서버가 발급한 원본 식별자
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 발화에서 온 근거인지 여부
   * @return 저장 가능한 원본 근거
   * @throws IllegalArgumentException 번호가 0 이하이거나 문장·식별자가 비었거나 파생 종류를 넘긴 경우
   */
  public static ReportEvidenceItem original(
      Report report,
      int evidenceNumber,
      ReportEvidenceSourceType sourceType,
      String text,
      ReportEvidenceSourceKind sourceRefKind,
      String sourceRefId,
      boolean sttNeedsConfirmation) {
    ReportEvidenceItem item =
        new ReportEvidenceItem(report, evidenceNumber, sourceType, text, sttNeedsConfirmation);
    if (sourceType.isDerived()) {
      throw new IllegalArgumentException(
          "derived sourceType must be created with derived(): " + sourceType);
    }
    item.sourceRefKind = Objects.requireNonNull(sourceRefKind, "sourceRefKind must not be null");
    item.sourceRefId = requireText(sourceRefId, "sourceRefId");
    return item;
  }

  /**
   * 다른 근거에서 파생된 근거를 생성한다.
   *
   * <p>파생 근거는 {@code sourceRef}를 갖지 않는다. 말단 원본까지 펼쳐 세는 계수 절차가 성립하려면 원본 참조가 최소 한 건 있어야 한다.
   *
   * @param report 근거가 속한 리포트
   * @param evidenceNumber 리포트 안에서 유일한 근거 번호(1 이상)
   * @param sourceType 파생 근거 종류({@code REPEATED_SUBJECT}·{@code LONGITUDINAL})
   * @param text 근거 문장
   * @param origins 원본 참조 목록이며 최소 1건이어야 한다
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 발화에서 온 근거인지 여부
   * @return 저장 가능한 파생 근거
   * @throws IllegalArgumentException 파생 종류가 아니거나 원본 참조가 비어 있는 경우
   */
  public static ReportEvidenceItem derived(
      Report report,
      int evidenceNumber,
      ReportEvidenceSourceType sourceType,
      String text,
      List<ReportEvidenceSourceRef> origins,
      boolean sttNeedsConfirmation) {
    ReportEvidenceItem item =
        new ReportEvidenceItem(report, evidenceNumber, sourceType, text, sttNeedsConfirmation);
    if (!sourceType.isDerived()) {
      throw new IllegalArgumentException(
          "non-derived sourceType must be created with original(): " + sourceType);
    }
    if (origins == null || origins.isEmpty()) {
      throw new IllegalArgumentException("derived evidence must reference at least one origin");
    }
    int order = 0;
    for (ReportEvidenceSourceRef origin : origins) {
      item.derivations.add(
          ReportEvidenceDerivation.create(item, order++, origin.kind(), origin.id()));
    }
    return item;
  }

  /**
   * @return 근거 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 응답의 {@code evidenceId}로 나가는 리포트 안 근거 번호
   */
  public int getEvidenceNumber() {
    return evidenceNumber;
  }

  /**
   * @return 근거 종류
   */
  public ReportEvidenceSourceType getSourceType() {
    return sourceType;
  }

  /**
   * @return 근거 문장
   */
  public String getText() {
    return text;
  }

  /**
   * @return 원본 참조이며 파생 근거면 빈 값
   */
  public java.util.Optional<ReportEvidenceSourceRef> getSourceRef() {
    return sourceRefKind == null
        ? java.util.Optional.empty()
        : java.util.Optional.of(new ReportEvidenceSourceRef(sourceRefKind, sourceRefId));
  }

  /**
   * @return 파생 근거의 원본 참조 목록이며 원본 근거면 빈 목록
   */
  public List<ReportEvidenceDerivation> getDerivations() {
    return Collections.unmodifiableList(derivations);
  }

  /**
   * @return 음성 인식 확인이 필요한 발화에서 온 근거인지 여부
   */
  public boolean isSttNeedsConfirmation() {
    return sttNeedsConfirmation;
  }

  /**
   * 파생 근거인지 확인한다.
   *
   * @return 원본 참조 없이 파생 목록을 갖는 근거면 {@code true}
   */
  public boolean isDerived() {
    return sourceRefKind == null;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
