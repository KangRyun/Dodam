package com.ssafy.b209.report.domain;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * REPORT-02 보호자용 그림 심리 상담 리포트 상세 조회 전용으로 {@code analyses} 한 행을 읽는 읽기 모델이다.
 *
 * <p>탐지 객체를 어느 분석에서 읽을지 판단하는 데 필요한 세션·범위·작업 유형·상태·요청 시각만 스칼라로 매핑한다. Model 정보와 오류 정보처럼 보호자에게 노출하지 않는
 * 컬럼은 읽지 않는다.
 *
 * <p>조회 조건과 정렬에만 쓰이는 Join 대상이라 값을 밖으로 내보내지 않는다. 따라서 Getter를 두지 않고 JPQL에서 Field 경로로만 참조한다.
 */
@Entity
@Table(name = "analyses")
public class ReportAnalysisView {

  @Id private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_type", nullable = false, length = 20)
  private DrawingAnalysisScope scope;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_task_type", nullable = false, length = 30)
  private DrawingAnalysisType taskType;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_status", nullable = false, length = 20)
  private DrawingAnalysisState state;

  @Column(name = "requested_at", nullable = false)
  private LocalDateTime requestedAt;

  protected ReportAnalysisView() {}
}
