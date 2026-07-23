package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code drawing_types} 한 행을 읽는 읽기 모델이다.
 *
 * <p>그림 활동 유형의 코드와 표시명만 읽어 리포트 응답에 노출한다.
 */
@Entity
@Table(name = "drawing_types")
public class ReportDrawingTypeView {

  @Id private Long id;

  @Column(name = "code", nullable = false)
  private String code;

  @Column(name = "name", nullable = false)
  private String name;

  protected ReportDrawingTypeView() {}

  /**
   * @return 그림 활동 유형 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 그림 활동 유형 코드
   */
  public String getCode() {
    return code;
  }

  /**
   * @return 그림 활동 유형 표시명
   */
  public String getName() {
    return name;
  }
}
