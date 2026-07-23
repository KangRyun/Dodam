package com.ssafy.b209.report.service;

import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 완료 접수 Transaction이 커밋된 뒤 관찰 리포트 생성을 실행한다.
 *
 * <p>커밋 후에 실행하므로 완료 응답(202)에는 영향을 주지 않으며, 생성 실패는 생성 서비스 내부에서 리포트 실패 상태로 흡수한다.
 */
@Component
public class ReportGenerationEventListener {

  private final MockObservationReportGenerationService generationService;

  /**
   * 관찰 리포트 생성 서비스를 주입받는다.
   *
   * @param generationService 관찰 리포트 생성 조율 서비스
   */
  public ReportGenerationEventListener(MockObservationReportGenerationService generationService) {
    this.generationService = generationService;
  }

  /**
   * 완료 접수 커밋 후 대기 중 분석의 관찰 리포트를 생성한다.
   *
   * @param event 생성 대상 분석 식별자를 담은 이벤트
   */
  @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
  public void onReportGenerationRequested(ReportGenerationRequestedEvent event) {
    generationService.generate(event.analysisId());
  }
}
