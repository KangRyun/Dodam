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
 * 이번 그림일기에서 <strong>확인하지 못한 것</strong>이다.
 *
 * <p>근거가 없어 카드를 비우면 보호자에게는 '문제가 없었다'로 읽힌다. 침묵 대신 무엇을 알 수 없었는지 이름을 붙여 돌려주기 위한 자리다.
 *
 * <p>코드와 문구를 **서버가 원자료에서 정한다**(건너뛴 질문·음성 인식 미확정·감정 없음·시점 불명 등). 모델에게 맡기면 '모르는 것'조차 지어낸다.
 */
@Entity
@Table(name = "report_diary_unknown_items")
public class ReportDiaryUnknownItem {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "code", nullable = false, length = 40)
  private String code;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryUnknownItem() {}

  private ReportDiaryUnknownItem(Report report, String code, String text, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.code = Objects.requireNonNull(code, "code must not be null");
    this.text = Objects.requireNonNull(text, "text must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 확인하지 못한 것을 만든다.
   *
   * @param report 소속 리포트
   * @param code 서버가 정한 코드
   * @param text 보호자에게 보이는 문구
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryUnknownItem create(
      Report report, String code, String text, int displayOrder) {
    return new ReportDiaryUnknownItem(report, code, text, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 서버가 정한 코드
   */
  public String getCode() {
    return code;
  }

  /**
   * @return 보호자에게 보이는 문구
   */
  public String getText() {
    return text;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
