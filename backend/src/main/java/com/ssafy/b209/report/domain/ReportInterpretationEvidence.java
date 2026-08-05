package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 경향 해석 카드와 근거를 잇는 연결이다.
 *
 * <p>근거 번호를 카드 쪽에 문자열·JSON 으로 담지 않고 FK 로 묶는다. 그래서 "존재하지 않는 근거를 참조한다"는 정합 오류가 애플리케이션 검증 이전에 DB 에서
 * 막힌다.
 */
@Entity
@Table(name = "report_interpretation_evidences")
public class ReportInterpretationEvidence {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "interpretation_id", nullable = false)
  private ReportPublicInterpretation interpretation;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "evidence_item_id", nullable = false)
  private ReportEvidenceItem evidenceItem;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportInterpretationEvidence() {}

  private ReportInterpretationEvidence(
      ReportPublicInterpretation interpretation,
      int displayOrder,
      ReportEvidenceItem evidenceItem) {
    this.interpretation = Objects.requireNonNull(interpretation, "interpretation must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.evidenceItem = Objects.requireNonNull(evidenceItem, "evidenceItem must not be null");
  }

  /**
   * 카드와 근거의 연결을 생성한다.
   *
   * @param interpretation 근거를 참조하는 카드
   * @param displayOrder 0부터 시작하는 근거 노출 순서
   * @param evidenceItem 참조되는 근거
   * @return 저장 가능한 연결
   * @throws IllegalArgumentException 순서가 음수인 경우
   */
  static ReportInterpretationEvidence create(
      ReportPublicInterpretation interpretation,
      int displayOrder,
      ReportEvidenceItem evidenceItem) {
    return new ReportInterpretationEvidence(interpretation, displayOrder, evidenceItem);
  }

  /**
   * @return 연결 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 0부터 시작하는 근거 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 참조되는 근거
   */
  public ReportEvidenceItem getEvidenceItem() {
    return evidenceItem;
  }
}
