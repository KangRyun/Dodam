package com.ssafy.b209.report.domain;

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
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 파생 근거가 어떤 원본에서 왔는지 담는 참조 한 건이다.
 *
 * <p>원본 참조를 JSON 한 컬럼에 담지 않고 행으로 정규화한다(V3 에서 정한 규칙). 덕분에 말단까지 펼쳐 세는 계수 절차를 SQL 로도 검증할 수 있다.
 */
@Entity
@Table(name = "report_evidence_derivations")
public class ReportEvidenceDerivation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "evidence_item_id", nullable = false)
  private ReportEvidenceItem evidenceItem;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Enumerated(EnumType.STRING)
  @Column(name = "source_ref_kind", nullable = false, length = 20)
  private ReportEvidenceSourceKind sourceRefKind;

  @Column(name = "source_ref_id", nullable = false, length = 64)
  private String sourceRefId;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportEvidenceDerivation() {}

  private ReportEvidenceDerivation(
      ReportEvidenceItem evidenceItem,
      int displayOrder,
      ReportEvidenceSourceKind sourceRefKind,
      String sourceRefId) {
    this.evidenceItem = Objects.requireNonNull(evidenceItem, "evidenceItem must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.sourceRefKind = Objects.requireNonNull(sourceRefKind, "sourceRefKind must not be null");
    if (sourceRefId == null || sourceRefId.isBlank()) {
      throw new IllegalArgumentException("sourceRefId must not be blank");
    }
    this.sourceRefId = sourceRefId;
  }

  /**
   * 파생 근거에 연결되는 원본 참조를 생성한다.
   *
   * @param evidenceItem 참조를 갖는 파생 근거
   * @param displayOrder 0부터 시작하는 참조 순서
   * @param sourceRefKind 원본 근거의 종류
   * @param sourceRefId 서버가 발급한 원본 식별자
   * @return 저장 가능한 원본 참조
   * @throws IllegalArgumentException 순서가 음수이거나 식별자가 비어 있는 경우
   */
  static ReportEvidenceDerivation create(
      ReportEvidenceItem evidenceItem,
      int displayOrder,
      ReportEvidenceSourceKind sourceRefKind,
      String sourceRefId) {
    return new ReportEvidenceDerivation(evidenceItem, displayOrder, sourceRefKind, sourceRefId);
  }

  /**
   * @return 원본 참조 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 0부터 시작하는 참조 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 원본 참조 값
   */
  public ReportEvidenceSourceRef getSourceRef() {
    return new ReportEvidenceSourceRef(sourceRefKind, sourceRefId);
  }
}
