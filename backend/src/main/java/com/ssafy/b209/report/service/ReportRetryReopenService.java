package com.ssafy.b209.report.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 재시도 직전에 분석과 리포트를 다시 생성 중으로 되돌린다 (S15P11B209 P0-2).
 *
 * <p>{@link MockObservationReportGenerationService#generate(Long)}는 <b>PENDING 분석</b>과
 * <b>GENERATING 리포트</b>만 다룬다. 실패한 상태 그대로 부르면 아무 일도 하지 않고 조용히 끝난다 — 워커가 매번 돌지만 아무것도 고쳐지지 않는 상태가 된다.
 *
 * <p>워커가 아니라 이 서비스가 Transaction 경계인 이유는, 되돌리기가 커밋된 뒤에야 {@code generate}가 그 상태를 읽을 수 있기 때문이다.
 */
@Service
public class ReportRetryReopenService {

  private final DrawingAnalysisRepository analysisRepository;
  private final ReportRepository reportRepository;
  private final Clock clock;

  /**
   * @param analysisRepository 최종 분석 저장소
   * @param reportRepository 리포트 저장소
   * @param clock 재시도 시각을 제공하는 UTC 시계
   */
  public ReportRetryReopenService(
      DrawingAnalysisRepository analysisRepository,
      ReportRepository reportRepository,
      Clock clock) {
    this.analysisRepository = analysisRepository;
    this.reportRepository = reportRepository;
    this.clock = clock;
  }

  /**
   * 재시도 가능한 실패를 다시 생성 중으로 되돌린다.
   *
   * <p>리포트와 분석 중 하나라도 되돌릴 수 없으면 아무것도 바꾸지 않는다. 리포트만 GENERATING 이고 분석은 FAILED 로 남으면 {@code generate}가
   * 맥락을 못 읽어, 리포트가 영원히 GENERATING 인 채로 멈춘다 — 실패보다 나쁜 상태다.
   *
   * @param reportId 리포트 식별자
   * @param analysisId 최종 분석 식별자
   * @return 되돌렸으면 {@code true}, 이미 다른 상태로 넘어갔으면 {@code false}
   */
  @Transactional
  public boolean reopen(long reportId, long analysisId) {
    Optional<Report> reportOptional =
        reportRepository
            .findByIdForUpdate(reportId)
            .filter(it -> it.getStatus().isRetryableFailure());
    Optional<DrawingAnalysis> analysisOptional = analysisRepository.findByIdForUpdate(analysisId);
    if (reportOptional.isEmpty() || analysisOptional.isEmpty()) {
      return false;
    }
    DrawingAnalysis analysis = analysisOptional.get();
    // 이미 PENDING 이면 되돌릴 것이 없다. 앞선 시도가 분석만 되돌리고 죽었을 때 이 상태가 되는데,
    //   여기서 물러나면 리포트는 FAILED_RETRYABLE 인 채로 아무도 다시 보지 않는다.
    if (!analysis.isPending()) {
      try {
        analysis.reopenForRetry();
      } catch (IllegalStateException exception) {
        // 성공했거나 다른 경로로 상태가 바뀐 분석이다. 리포트도 건드리지 않고 물러난다.
        return false;
      }
    }
    reportOptional.get().reopenForRetry(LocalDateTime.now(clock));
    return true;
  }

  /**
   * @param reportId 리포트 식별자
   * @return 리포트가 완료 상태면 {@code true}
   */
  @Transactional(readOnly = true)
  public boolean isCompleted(long reportId) {
    return reportRepository
        .findById(reportId)
        .filter(report -> report.getStatus() == ReportStatus.COMPLETED)
        .isPresent();
  }
}
