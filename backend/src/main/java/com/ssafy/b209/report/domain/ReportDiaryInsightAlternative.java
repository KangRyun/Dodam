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
 * 그림일기 인사이트의 '다르게 볼 수 있는 설명'이다.
 *
 * <p><strong>가설의 필수 짝</strong>이다. 해석을 하나만 제시하면 보호자는 그것을 결론으로 읽는다 — "다르게 볼 수도 있다"가 카드 안에 함께 있어야 가설이
 * 가설로 남는다. 그래서 이 행이 없으면 서버가 {@code SESSION_HYPOTHESIS} 카드를 아예 만들지 않는다.
 *
 * <p>{@code observationOrder} 는 소유 카드의 {@code displayOrder} 다({@link ReportDiaryEvidenceRef} 와 같은
 * 이유로 PK 대신 순서로 잇는다).
 */
@Entity
@Table(name = "report_diary_insight_alternatives")
public class ReportDiaryInsightAlternative {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "observation_order", nullable = false, columnDefinition = "SMALLINT")
  private int observationOrder;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryInsightAlternative() {}

  private ReportDiaryInsightAlternative(
      Report report, int observationOrder, String text, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.observationOrder = observationOrder;
    this.text = Objects.requireNonNull(text, "text must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 다른 설명을 만든다.
   *
   * @param report 소속 리포트
   * @param observationOrder 소유 카드의 노출 순서
   * @param text 다르게 볼 수 있는 설명 한 문장
   * @param displayOrder 카드 안에서의 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryInsightAlternative create(
      Report report, int observationOrder, String text, int displayOrder) {
    return new ReportDiaryInsightAlternative(report, observationOrder, text, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 카드의 노출 순서
   */
  public int getObservationOrder() {
    return observationOrder;
  }

  /**
   * @return 다르게 볼 수 있는 설명
   */
  public String getText() {
    return text;
  }

  /**
   * @return 카드 안에서의 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
