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
 * 유형별 보호자 가이드 문장 한 건이다.
 *
 * <p>유형마다 문장이 여러 개일 수 있어 유형 안에서의 순서를 함께 갖는다. 유형이 없으면 해당 화면 섹션이 숨는다(계약 §7).
 */
@Entity
@Table(name = "report_parent_guides")
public class ReportParentGuide {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Enumerated(EnumType.STRING)
  @Column(name = "guide_type", nullable = false, length = 30)
  private ReportParentGuideType guideType;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "guidance", nullable = false, columnDefinition = "TEXT")
  private String guidance;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportParentGuide() {}

  private ReportParentGuide(
      Report report, ReportParentGuideType guideType, int displayOrder, String guidance) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.guideType = Objects.requireNonNull(guideType, "guideType must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    if (guidance == null || guidance.isBlank()) {
      throw new IllegalArgumentException("guidance must not be blank");
    }
    this.guidance = guidance;
  }

  /**
   * 보호자 가이드 문장을 생성한다.
   *
   * @param report 가이드가 속한 리포트
   * @param guideType 가이드 유형
   * @param displayOrder 유형 안에서 0부터 시작하는 순서
   * @param guidance 화면에 그대로 나가는 완결 문장
   * @return 저장 가능한 보호자 가이드
   * @throws IllegalArgumentException 순서가 음수이거나 문장이 빈 경우
   */
  public static ReportParentGuide create(
      Report report, ReportParentGuideType guideType, int displayOrder, String guidance) {
    return new ReportParentGuide(report, guideType, displayOrder, guidance);
  }

  /**
   * @return 가이드 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 가이드 유형
   */
  public ReportParentGuideType getGuideType() {
    return guideType;
  }

  /**
   * @return 유형 안에서 0부터 시작하는 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 화면에 그대로 나가는 완결 문장
   */
  public String getGuidance() {
    return guidance;
  }
}
