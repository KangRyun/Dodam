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
 * 리포트의 관찰 특징을 노출 범위와 함께 저장한다.
 *
 * <p>전문가 검토를 마치지 않은 관찰 특징은 {@link ReportFeatureVisibility#EXPERT_ONLY}로 저장하여 보호자 노출 경로로 새지 않게 한다.
 */
@Entity
@Table(name = "report_observed_features")
public class ReportObservedFeature {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "feature_code", length = 80)
  private String featureCode;

  @Column(name = "title", length = 200)
  private String title;

  @Column(name = "description", nullable = false, columnDefinition = "TEXT")
  private String description;

  @Column(name = "evidence_summary", columnDefinition = "TEXT")
  private String evidenceSummary;

  @Enumerated(EnumType.STRING)
  @Column(name = "visibility_scope", nullable = false, length = 20)
  private ReportFeatureVisibility visibilityScope;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportObservedFeature() {}

  private ReportObservedFeature(
      Report report,
      String featureCode,
      String title,
      String description,
      String evidenceSummary,
      ReportFeatureVisibility visibilityScope,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.featureCode = featureCode;
    this.title = title;
    this.description = requireText(description, "description");
    this.evidenceSummary = evidenceSummary;
    this.visibilityScope =
        Objects.requireNonNull(visibilityScope, "visibilityScope must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트에 연결되는 관찰 특징을 생성한다.
   *
   * @param report 관찰 특징이 속한 리포트
   * @param featureCode 관찰 특징 코드이며 없으면 {@code null}
   * @param title 관찰 제목이며 없으면 {@code null}
   * @param description 관찰 내용
   * @param evidenceSummary 관찰 근거 요약이며 없으면 {@code null}
   * @param visibilityScope 노출 범위
   * @param displayOrder 0부터 시작하는 노출 순서
   * @return 저장 가능한 관찰 특징
   * @throws IllegalArgumentException 관찰 내용이 비었거나 순서가 음수인 경우
   */
  public static ReportObservedFeature create(
      Report report,
      String featureCode,
      String title,
      String description,
      String evidenceSummary,
      ReportFeatureVisibility visibilityScope,
      int displayOrder) {
    return new ReportObservedFeature(
        report, featureCode, title, description, evidenceSummary, visibilityScope, displayOrder);
  }

  /**
   * @return 관찰 특징 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 관찰 특징 코드이며 없으면 {@code null}
   */
  public String getFeatureCode() {
    return featureCode;
  }

  /**
   * @return 관찰 제목이며 없으면 {@code null}
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 관찰 내용
   */
  public String getDescription() {
    return description;
  }

  /**
   * @return 관찰 근거 요약이며 없으면 {@code null}
   */
  public String getEvidenceSummary() {
    return evidenceSummary;
  }

  /**
   * @return 노출 범위
   */
  public ReportFeatureVisibility getVisibilityScope() {
    return visibilityScope;
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
