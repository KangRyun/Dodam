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
 * 주제별 관찰과 경향 해석 카드의 연결이다 (875 §5 {@code interpretationRefs}).
 *
 * <p>AI 는 이 참조를 <strong>자기 응답 배열의 인덱스</strong>로 보낸다. 그 숫자를 그대로 저장하지 않고 카드 행을 FK 로 묶는 이유는 서버 2단 검증에서
 * 카드가 빠지면 보호자 응답 배열이 밀려 <strong>같은 숫자가 조용히 다른 카드를 가리키기</strong> 때문이다(875 §5-1). 응답에 실을 인덱스는 조회 시점에
 * 공개된 카드 목록에서의 위치로 다시 계산한다.
 */
@Entity
@Table(name = "report_subject_interpretations")
public class ReportSubjectInterpretation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_subject_id", nullable = false)
  private ReportSubject subject;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "interpretation_id", nullable = false)
  private ReportPublicInterpretation interpretation;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportSubjectInterpretation() {}

  private ReportSubjectInterpretation(
      ReportSubject subject, int displayOrder, ReportPublicInterpretation interpretation) {
    this.subject = Objects.requireNonNull(subject, "subject must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.interpretation = Objects.requireNonNull(interpretation, "interpretation must not be null");
  }

  /**
   * 주제와 경향 해석 카드의 연결을 생성한다.
   *
   * @param subject 참조하는 주제별 관찰 묶음
   * @param displayOrder 0부터 시작하는 참조 순서
   * @param interpretation 연결할 경향 해석 카드
   * @return 저장 가능한 연결
   * @throws IllegalArgumentException 순서가 음수인 경우
   */
  public static ReportSubjectInterpretation create(
      ReportSubject subject, int displayOrder, ReportPublicInterpretation interpretation) {
    return new ReportSubjectInterpretation(subject, displayOrder, interpretation);
  }

  /**
   * @return 연결 식별자
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
   * @return 연결된 경향 해석 카드
   */
  public ReportPublicInterpretation getInterpretation() {
    return interpretation;
  }
}
