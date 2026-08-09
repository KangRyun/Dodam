package com.ssafy.b209.report.service;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

/**
 * 재시도 워커가 되살릴 것만 되살리고, 끝난 작업은 대기열에서 내리는지 확인한다 (S15P11B209 P0-2).
 *
 * <p>이 워커가 잘못 돌면 두 방향으로 나쁘다 — 안 되살리면 보호자는 빈 리포트를 계속 보고, 끝난 작업을 안 내리면 같은 리포트를 두고 AI 를 반복해서 부른다.
 */
@ExtendWith(MockitoExtension.class)
class ReportGenerationRetryWorkerTest {

  private static final ReportGenerationRetry JOB =
      new ReportGenerationRetry(1L, 100L, 200L, 1, "corr-1");

  @Mock private ReportGenerationRetryRepository retryRepository;
  @Mock private ReportRetryReopenService reopenService;
  @Mock private MockObservationReportGenerationService generationService;
  @Mock private ApplicationEventPublisher eventPublisher;

  private ReportGenerationRetryWorker worker() {
    return new ReportGenerationRetryWorker(
        retryRepository, reopenService, generationService, eventPublisher);
  }

  @Test
  void resolvesJobWhenRegenerationSucceeds() {
    given(retryRepository.claim(anyInt(), any(Duration.class), anyInt())).willReturn(List.of(JOB));
    given(reopenService.reopen(100L, 200L)).willReturn(true);
    given(reopenService.isCompleted(100L)).willReturn(true);

    worker().retryFailedReports();

    verify(generationService).generate(200L);
    verify(retryRepository).resolve(1L);
  }

  /** 다시 실패했으면 행을 남긴다. 다음 틱이 남은 시도 횟수 안에서 또 집는다. */
  @Test
  void keepsJobQueuedWhenRegenerationFailsAgain() {
    given(retryRepository.claim(anyInt(), any(Duration.class), anyInt())).willReturn(List.of(JOB));
    given(reopenService.reopen(100L, 200L)).willReturn(true);
    given(reopenService.isCompleted(100L)).willReturn(false);

    worker().retryFailedReports();

    verify(generationService).generate(200L);
    verify(retryRepository, never()).resolve(anyLong());
  }

  /**
   * 그사이 다른 경로가 리포트를 끝냈으면 다시 만들지 않는다.
   *
   * <p>이걸 안 지키면 이미 완료된 리포트를 GENERATING 으로 되돌려 보호자 화면에서 결과가 사라진다.
   */
  @Test
  void skipsRegenerationWhenReportLeftRetryableState() {
    given(retryRepository.claim(anyInt(), any(Duration.class), anyInt())).willReturn(List.of(JOB));
    given(reopenService.reopen(100L, 200L)).willReturn(false);

    worker().retryFailedReports();

    verify(generationService, never()).generate(anyLong());
    verify(retryRepository).resolve(1L);
  }

  /** 한 건이 터져도 배치를 멈추지 않는다. 멈추면 그 뒤 보호자들이 통째로 리포트를 못 받는다. */
  @Test
  void absorbsFailureOfOneJobAndContinues() {
    ReportGenerationRetry second = new ReportGenerationRetry(2L, 101L, 201L, 1, "corr-2");
    given(retryRepository.claim(anyInt(), any(Duration.class), anyInt()))
        .willReturn(List.of(JOB, second));
    given(reopenService.reopen(100L, 200L)).willThrow(new IllegalStateException("boom"));
    given(reopenService.reopen(101L, 201L)).willReturn(true);
    given(reopenService.isCompleted(101L)).willReturn(true);

    worker().retryFailedReports();

    verify(generationService).generate(201L);
    verify(retryRepository).resolve(2L);
  }

  /** 대기열 정리가 터지면 그 틱은 아무것도 집지 않는다. 잘못된 시도 횟수로 판단하는 것보다 낫다. */
  @Test
  void skipsTickWhenQueueMaintenanceFails() {
    given(retryRepository.adopt(anyInt())).willThrow(new IllegalStateException("db down"));

    worker().retryFailedReports();

    verify(retryRepository, never()).claim(anyInt(), any(Duration.class), anyInt());
    verify(generationService, never()).generate(anyLong());
  }

  /**
   * 재시도를 다 써서 포기한 리포트는 보호자에게 알린다.
   *
   * <p>이 경로가 비면 실패가 조용히 묻힌다 — 포기 처리는 {@code markFailed}를 지나지 않아 그쪽에 붙은 알림이 닿지 않고, 아이 화면은 리포트를 기다리지
   * 않고 넘어가므로 어디에도 실패가 뜨지 않는다.
   */
  @Test
  void notifiesGuardianForEachAbandonedReport() {
    given(retryRepository.abandonExhausted(anyInt())).willReturn(List.of(100L, 101L));

    worker().retryFailedReports();

    verify(eventPublisher).publishEvent(new ReportGenerationFailedEvent(100L));
    verify(eventPublisher).publishEvent(new ReportGenerationFailedEvent(101L));
  }

  /** 포기한 리포트가 없으면 알리지 않는다. */
  @Test
  void doesNotNotifyWhenNothingAbandoned() {
    given(retryRepository.abandonExhausted(anyInt())).willReturn(List.of());

    worker().retryFailedReports();

    verify(eventPublisher, never()).publishEvent(org.mockito.ArgumentMatchers.<Object>any());
  }

  /**
   * 알림 요청이 터져도 재시도 배치는 계속 돈다.
   *
   * <p>알림은 부수효과이고 재생성이 본 일이다. 여기서 예외가 새면 그 틱의 리포트들이 통째로 재생성 기회를 잃는다.
   */
  @Test
  void continuesBatchWhenAbandonNotificationFails() {
    given(retryRepository.abandonExhausted(anyInt())).willReturn(List.of(100L));
    org.mockito.BDDMockito.willThrow(new IllegalStateException("event bus down"))
        .given(eventPublisher)
        .publishEvent(new ReportGenerationFailedEvent(100L));
    given(retryRepository.claim(anyInt(), any(Duration.class), anyInt())).willReturn(List.of(JOB));
    given(reopenService.reopen(100L, 200L)).willReturn(true);
    given(reopenService.isCompleted(100L)).willReturn(true);

    worker().retryFailedReports();

    verify(generationService).generate(200L);
    verify(retryRepository).resolve(1L);
  }

  private static <T> T any(Class<T> type) {
    return org.mockito.ArgumentMatchers.any(type);
  }
}
