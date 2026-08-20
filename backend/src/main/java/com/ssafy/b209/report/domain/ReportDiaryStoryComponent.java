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
 * 그림일기 V3의 사건·행동·감정 등 이야기 구성 요소 하나를 보존한다.
 *
 * <p>확인 상태를 내용과 분리해 저장하므로, 보호자 화면은 아이가 말한 사실과 그림에서만 보인 사실 및 아직 모르는 내용을 구분할 수 있다.
 */
@Entity
@Table(name = "report_diary_story_components")
public class ReportDiaryStoryComponent {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "component_type", nullable = false, length = 30)
  private String componentType;

  @Column(name = "confirmation_status", nullable = false, length = 20)
  private String confirmationStatus;

  @Column(name = "text", columnDefinition = "TEXT")
  private String text;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryStoryComponent() {}

  private ReportDiaryStoryComponent(
      Report report,
      String componentType,
      String confirmationStatus,
      String text,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.componentType = Objects.requireNonNull(componentType, "componentType must not be null");
    this.confirmationStatus =
        Objects.requireNonNull(confirmationStatus, "confirmationStatus must not be null");
    this.text = text;
    this.displayOrder = displayOrder;
  }

  /**
   * 검증을 마친 이야기 구성 요소를 만든다.
   *
   * @param report 소속 리포트
   * @param componentType 이야기 구성 요소 종류
   * @param confirmationStatus 근거 확인 상태
   * @param text 확인된 내용이며 상태가 UNKNOWN이면 {@code null} 가능
   * @param displayOrder 화면 표시 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryStoryComponent create(
      Report report,
      String componentType,
      String confirmationStatus,
      String text,
      int displayOrder) {
    return new ReportDiaryStoryComponent(
        report, componentType, confirmationStatus, text, displayOrder);
  }

  /**
   * @return 이야기 구성 요소 종류
   */
  public String getComponentType() {
    return componentType;
  }

  /**
   * @return 근거 확인 상태
   */
  public String getConfirmationStatus() {
    return confirmationStatus;
  }

  /**
   * @return 확인된 내용이며 UNKNOWN이면 {@code null}
   */
  public String getText() {
    return text;
  }

  /**
   * @return 화면 표시 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
