package com.ssafy.b209.report.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OneToOne;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;

/**
 * 리포트 위기 대응 안내다 (S15P11B209-902 / 계약 §4-4).
 *
 * <p>보호자 가이드와 다른 필드다 — 가이드의 {@code PROFESSIONAL_SUPPORT}는 상시 노출되는 일반 상담 안내이고 이쪽은 위기 신호가 있을 때만 생기는
 * 사전 검토 템플릿이다. 행이 없으면 위기 신호가 없다는 뜻이며 별도 플래그를 두지 않는다.
 *
 * <p><strong>{@code ABUSE_DISCLOSURE}는 저장할 수 없다.</strong> 가해자가 보호자일 수 있어 자동 통지가 아이를 위험하게 하므로 AI 가 이
 * 값을 만들지 않고(S15P11B209-890), DB CHECK 와 이 팩토리에서도 막아 매핑이 되돌아가도 보호자 노출 경로로 새지 않게 한다. 신호는 전문가 검토 필요
 * 표시로만 남는다.
 */
@Entity
@Table(name = "report_crisis_alerts")
public class ReportCrisisAlert {

  private static final Set<String> ALLOWED_REASONS = Set.of("SELF_HARM_RISK", "CRISIS_INTENT");
  private static final Set<String> ALLOWED_SEVERITIES = Set.of("HIGH", "ELEVATED");

  @Id
  @Column(name = "report_id")
  private Long reportId;

  @OneToOne(fetch = FetchType.LAZY, optional = false)
  @MapsId
  @JoinColumn(name = "report_id")
  private Report report;

  @Column(name = "reason_code", nullable = false, length = 30)
  private String reasonCode;

  @Column(name = "severity", nullable = false, length = 10)
  private String severity;

  @Column(name = "title", nullable = false, length = 200)
  private String title;

  @Column(name = "message", nullable = false, columnDefinition = "TEXT")
  private String message;

  @OneToMany(mappedBy = "crisisAlert", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("displayOrder ASC")
  private List<ReportCrisisAlertStep> steps = new ArrayList<>();

  @OneToMany(mappedBy = "crisisAlert", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("displayOrder ASC")
  private List<ReportCrisisAlertResource> resources = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportCrisisAlert() {}

  private ReportCrisisAlert(
      Report report, String reasonCode, String severity, String title, String message) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.reasonCode = requireAllowed(reasonCode, ALLOWED_REASONS, "reasonCode");
    this.severity = requireAllowed(severity, ALLOWED_SEVERITIES, "severity");
    this.title = requireText(title, "title");
    this.message = requireText(message, "message");
  }

  /**
   * 위기 대응 안내를 생성한다.
   *
   * @param report 안내가 속한 리포트
   * @param reasonCode 위기 사유 코드({@code SELF_HARM_RISK}·{@code CRISIS_INTENT})
   * @param severity 심각도({@code HIGH}·{@code ELEVATED})
   * @param title 안내 제목
   * @param message 안내 본문
   * @return 저장 가능한 위기 대응 안내
   * @throws IllegalArgumentException 허용하지 않는 사유·심각도이거나 제목·본문이 빈 경우
   */
  public static ReportCrisisAlert create(
      Report report, String reasonCode, String severity, String title, String message) {
    return new ReportCrisisAlert(report, reasonCode, severity, title, message);
  }

  /**
   * 보호자가 취할 행동 단계를 순서대로 추가한다.
   *
   * @param stepText 행동 문구
   */
  public void addStep(String stepText) {
    steps.add(ReportCrisisAlertStep.create(this, steps.size(), stepText));
  }

  /**
   * 상담·신고 자원을 순서대로 추가한다.
   *
   * @param name 자원 이름
   * @param contact 연락처
   * @param note 보충 설명이며 없으면 빈 문자열로 저장한다
   */
  public void addResource(String name, String contact, String note) {
    resources.add(ReportCrisisAlertResource.create(this, resources.size(), name, contact, note));
  }

  /**
   * 저장 가능한 위기 사유인지 확인한다.
   *
   * <p>호출 측이 저장 전에 걸러 쓰도록 공개한다 — 금지 사유로 팩토리를 부르면 예외가 나고, 위기 안내 한 건 때문에 리포트 저장 전체가 실패한다.
   *
   * @param reasonCode 확인할 사유 코드
   * @return 보호자 통지가 허용된 사유면 {@code true}
   */
  public static boolean isStorableReason(String reasonCode) {
    return reasonCode != null
        && ALLOWED_REASONS.contains(reasonCode.trim().toUpperCase(Locale.ROOT));
  }

  /**
   * @return 리포트 식별자
   */
  public Long getReportId() {
    return reportId;
  }

  /**
   * @return 위기 사유 코드
   */
  public String getReasonCode() {
    return reasonCode;
  }

  /**
   * @return 심각도
   */
  public String getSeverity() {
    return severity;
  }

  /**
   * @return 안내 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 안내 본문
   */
  public String getMessage() {
    return message;
  }

  /**
   * @return 행동 단계 목록
   */
  public List<ReportCrisisAlertStep> getSteps() {
    return Collections.unmodifiableList(steps);
  }

  /**
   * @return 상담·신고 자원 목록
   */
  public List<ReportCrisisAlertResource> getResources() {
    return Collections.unmodifiableList(resources);
  }

  private static String requireAllowed(String value, Set<String> allowed, String name) {
    String normalized = requireText(value, name).trim().toUpperCase(Locale.ROOT);
    if (!allowed.contains(normalized)) {
      throw new IllegalArgumentException(name + " must be one of " + allowed);
    }
    return normalized;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
