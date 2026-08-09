package com.ssafy.b209.report.service;

import java.time.Duration;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 재시도 가능한 실패로 남은 리포트를 다시 만든다 (S15P11B209 P0-2).
 *
 * <p><b>왜 필요한가.</b> 활동 완료와 리포트 생성을 떼어 놓으면서, 리포트가 실패해도 아이 화면은 정상적으로 끝나게 됐다. 좋은 일이지만 그만큼 실패가 조용해졌다 —
 * 예전에는 활동이 FAILED로 눈에 띄었다면 이제는 보호자만 빈 리포트를 본다. 상류가 잠깐 흔들려 실패한 것이라면 사람 손을 거치지 않고 되살아나야 한다.
 *
 * <p><b>되살릴 것과 아닌 것을 가른다.</b> {@code FAILED_RETRYABLE}만 집는다. 근거 부족이나 응답 계약 위반({@code
 * FAILED_FINAL})은 몇 번을 더 불러도 같은 자리에서 멈추므로 AI 호출만 낭비한다.
 *
 * <p><b>개별 실패를 흡수한다.</b> 한 건이 배치를 멈추면 그 뒤의 보호자들이 통째로 리포트를 못 받는다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.report.retry",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = true)
public class ReportGenerationRetryWorker {

  private static final Logger log = LoggerFactory.getLogger(ReportGenerationRetryWorker.class);
  private static final int BATCH_SIZE = 10;
  private static final int MAX_ATTEMPTS = 3;
  private static final Duration LEASE = Duration.ofMinutes(5);

  private final ReportGenerationRetryRepository retryRepository;
  private final ReportRetryReopenService reopenService;
  private final MockObservationReportGenerationService generationService;
  private final ApplicationEventPublisher eventPublisher;

  /**
   * @param retryRepository 재시도 대기열 저장소
   * @param reopenService 분석·리포트를 다시 생성 중으로 되돌리는 Transaction 경계
   * @param generationService 실제 재생성을 수행하는 서비스
   * @param eventPublisher 재시도를 포기한 리포트의 보호자 실패 알림을 요청할 이벤트 발행기
   */
  public ReportGenerationRetryWorker(
      ReportGenerationRetryRepository retryRepository,
      ReportRetryReopenService reopenService,
      MockObservationReportGenerationService generationService,
      ApplicationEventPublisher eventPublisher) {
    this.retryRepository = retryRepository;
    this.reopenService = reopenService;
    this.generationService = generationService;
    this.eventPublisher = eventPublisher;
  }

  /** 대기열을 채우고, 시각이 된 작업을 다시 생성하고, 한도를 다 쓴 작업을 내린다. */
  @Scheduled(fixedDelayString = "${app.report.retry.interval:2m}")
  public void retryFailedReports() {
    try {
      retryRepository.adopt(BATCH_SIZE);
      List<Long> abandoned = retryRepository.abandonExhausted(MAX_ATTEMPTS);
      if (!abandoned.isEmpty()) {
        log.warn("리포트 재시도를 포기했습니다. count={}, maxAttempts={}", abandoned.size(), MAX_ATTEMPTS);
        notifyAbandoned(abandoned);
      }
    } catch (RuntimeException exception) {
      log.error("리포트 재시도 대기열 정리에 실패했습니다.", exception);
      return;
    }

    List<ReportGenerationRetry> claimed = retryRepository.claim(BATCH_SIZE, LEASE, MAX_ATTEMPTS);
    for (ReportGenerationRetry retry : claimed) {
      retryOne(retry);
    }
  }

  /**
   * 포기한 리포트마다 보호자 실패 알림을 요청한다.
   *
   * <p><b>여기서 알리지 않으면 아무도 알리지 않는다.</b> 재시도를 다 쓴 실패는 {@code markFailed}를 지나지 않고 대기열 정리가 상태만 바꾸므로, 그
   * 경로에 붙은 알림이 이 리포트에는 닿지 않는다. 아이 화면은 리포트를 기다리지 않고 넘어가므로 실패가 어디에도 뜨지 않는다.
   *
   * <p><b>알림 실패가 재시도 배치를 멈추지 않게 한다.</b> 한 건이 던지면 뒤의 리포트들이 통째로 재생성 기회를 잃는다 — 알림은 부수효과이고 재시도가 본 일이다.
   *
   * @param reportIds 최종 실패로 내려간 리포트 식별자 목록
   */
  private void notifyAbandoned(List<Long> reportIds) {
    for (Long reportId : reportIds) {
      try {
        eventPublisher.publishEvent(new ReportGenerationFailedEvent(reportId));
      } catch (RuntimeException exception) {
        log.warn(
            "리포트 재시도 포기 알림 요청에 실패했습니다. reportId={}, reason={}",
            reportId,
            exception.getClass().getSimpleName());
      }
    }
  }

  private void retryOne(ReportGenerationRetry retry) {
    log.info(
        "리포트 재생성을 시작합니다. reportId={}, analysisId={}, attempt={}, correlationId={}",
        retry.reportId(),
        retry.analysisId(),
        retry.attemptCount(),
        retry.correlationId());
    try {
      if (!reopenService.reopen(retry.reportId(), retry.analysisId())) {
        // 그사이 누군가 완료시켰거나 최종 실패로 내렸다. 대기열에서 내리는 게 맞다.
        retryRepository.resolve(retry.id());
        return;
      }
      generationService.generate(retry.analysisId());
      if (reopenService.isCompleted(retry.reportId())) {
        retryRepository.resolve(retry.id());
        log.info(
            "리포트 재생성에 성공했습니다. reportId={}, attempt={}", retry.reportId(), retry.attemptCount());
      }
      // 다시 실패했으면 대기열에 남긴다. generate() 가 리포트 상태에 재시도 여부를 이미 기록했고,
      //   그것이 FAILED_FINAL 이면 다음 claim 이 걸러 낸다.
    } catch (RuntimeException exception) {
      log.error(
          "리포트 재생성 중 예기치 못한 오류가 발생했습니다. reportId={}, attempt={}",
          retry.reportId(),
          retry.attemptCount(),
          exception);
    }
  }
}
