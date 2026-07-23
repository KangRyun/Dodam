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

/** 보호자가 활용할 후속 안내 문구를 노출 순서와 함께 저장한다. */
@Entity
@Table(name = "report_follow_up_guides")
public class ReportFollowUpGuide {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "guidance", nullable = false, columnDefinition = "TEXT")
  private String guidance;

  @Column(name = "detail_text", columnDefinition = "TEXT")
  private String detailText;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportFollowUpGuide() {}

  private ReportFollowUpGuide(Report report, String guidance, String detailText, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.guidance = requireText(guidance, "guidance");
    this.detailText = detailText;
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트에 연결되는 후속 안내를 생성한다.
   *
   * @param report 안내가 속한 리포트
   * @param guidance 보호자 안내 문장
   * @param detailText 상세 설명이며 없으면 {@code null}
   * @param displayOrder 0부터 시작하는 노출 순서
   * @return 저장 가능한 후속 안내
   * @throws IllegalArgumentException 안내 문장이 비었거나 순서가 음수인 경우
   */
  public static ReportFollowUpGuide create(
      Report report, String guidance, String detailText, int displayOrder) {
    return new ReportFollowUpGuide(report, guidance, detailText, displayOrder);
  }

  /**
   * @return 후속 안내 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 보호자 안내 문장
   */
  public String getGuidance() {
    return guidance;
  }

  /**
   * @return 상세 설명이며 없으면 {@code null}
   */
  public String getDetailText() {
    return detailText;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
