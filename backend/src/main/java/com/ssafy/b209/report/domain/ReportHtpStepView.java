package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 그림 심리 상담 리포트 상세 조회 전용으로 {@code htp_assessment_steps} 한 행을 읽는 읽기 모델이다.
 *
 * <p>집·나무·사람 리포트는 세 그림 세션의 사실을 한 리포트로 묶어 보여 준다. 리포트가 가리키는 세션에서 형제 세션을 찾고 주제 순서대로 정렬하기 위해 묶음
 * 식별자·순서·세션 식별자만 읽는다.
 *
 * <p>조회 조건과 정렬에만 쓰이는 Join 대상이라 값을 밖으로 내보내지 않는다. 따라서 Getter를 두지 않고 JPQL에서 Field 경로로만 참조한다.
 */
@Entity
@Table(name = "htp_assessment_steps")
public class ReportHtpStepView {

  @Id private Long id;

  @Column(name = "htp_assessment_id", nullable = false)
  private Long assessmentId;

  @Column(name = "step_order", nullable = false, columnDefinition = "TINYINT")
  private Integer stepOrder;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  protected ReportHtpStepView() {}
}
