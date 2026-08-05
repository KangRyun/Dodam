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
 * 주제별 관찰 서술 한 줄이다 (875 §5 {@code visionObservations}).
 *
 * <p><strong>눈으로 확인된 사실만 담는다.</strong> 해석은 이 자리가 아니라 경향 해석 카드({@link ReportPublicInterpretation})의
 * 몫이다 — 사실과 해석을 같은 줄에 섞으면 보호자가 관찰을 진단으로 읽는다.
 */
@Entity
@Table(name = "report_subject_observations")
public class ReportSubjectObservation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_subject_id", nullable = false)
  private ReportSubject subject;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "observation_text", nullable = false, columnDefinition = "TEXT")
  private String observationText;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportSubjectObservation() {}

  private ReportSubjectObservation(
      ReportSubject subject, int displayOrder, String observationText) {
    this.subject = Objects.requireNonNull(subject, "subject must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    if (observationText == null || observationText.isBlank()) {
      throw new IllegalArgumentException("observationText must not be blank");
    }
    this.observationText = observationText;
  }

  /**
   * 주제에 연결되는 관찰 서술 한 줄을 생성한다.
   *
   * @param subject 서술이 속한 주제별 관찰 묶음
   * @param displayOrder 0부터 시작하는 노출 순서
   * @param observationText 눈으로 확인된 사실 문장
   * @return 저장 가능한 관찰 서술
   * @throws IllegalArgumentException 순서가 음수이거나 문장이 빈 경우
   */
  public static ReportSubjectObservation create(
      ReportSubject subject, int displayOrder, String observationText) {
    return new ReportSubjectObservation(subject, displayOrder, observationText);
  }

  /**
   * @return 관찰 서술 식별자
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
   * @return 눈으로 확인된 사실 문장
   */
  public String getObservationText() {
    return observationText;
  }
}
