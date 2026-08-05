package com.ssafy.b209.storage.deletion;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;

import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 워커의 결과 분기 검증 (S15P11B209-780).
 *
 * <p>여기서 지키려는 것은 "실패한 삭제가 조용히 사라지지 않는다"이다. 잡이 COMPLETED 로 지워지면 어떤 아동 파일이 안 지워졌는지 알 방법이 없다(가드레일 9절).
 */
@ExtendWith(MockitoExtension.class)
class StorageDeletionWorkerTest {

  @Mock private StorageDeletionJobRepository jobRepository;
  @Mock private StorageDeletionRouter router;

  private StorageDeletionProperties properties;
  private StorageDeletionWorker worker;

  @BeforeEach
  void setUp() {
    properties = new StorageDeletionProperties();
    properties.setBatchSize(10);
    properties.setMaxRetryCount(3);
    properties.setStuckAfter(Duration.ofMinutes(10));
    worker = new StorageDeletionWorker(jobRepository, router, properties);
  }

  private static StorageDeletionJob job(long id, int retryCount) {
    return new StorageDeletionJob(id, "2026/08/key.bin", "DRAWING_ASSET", retryCount);
  }

  @Test
  @DisplayName("성공한 삭제는 완료 처리한다")
  void marksCompletedOnSuccess() {
    given(jobRepository.claim(anyInt())).willReturn(List.of(job(1L, 0)));

    worker.deletePendingObjects();

    then(jobRepository).should().markCompleted(1L);
    then(jobRepository).should(never()).markRetry(anyLong(), anyString());
    then(jobRepository).should(never()).markFailed(anyLong(), anyString());
  }

  @Test
  @DisplayName("재시도 예산이 남았으면 PENDING 으로 되돌린다")
  void marksRetryWhenBudgetRemains() {
    given(jobRepository.claim(anyInt())).willReturn(List.of(job(1L, 0)));
    willThrow(new IllegalStateException("boom")).given(router).delete(any());

    worker.deletePendingObjects();

    then(jobRepository).should().markRetry(eq(1L), anyString());
    then(jobRepository).should(never()).markFailed(anyLong(), anyString());
  }

  @Test
  @DisplayName("재시도 예산을 소진하면 FAILED 로 확정한다 — 행은 남겨 목록에서 보이게 한다")
  void marksFailedWhenBudgetExhausted() {
    // maxRetryCount=3, 이미 2회 실패 → 이번이 3번째라 확정
    given(jobRepository.claim(anyInt())).willReturn(List.of(job(1L, 2)));
    willThrow(new IllegalStateException("boom")).given(router).delete(any());

    worker.deletePendingObjects();

    then(jobRepository).should().markFailed(eq(1L), anyString());
    then(jobRepository).should(never()).markRetry(anyLong(), anyString());
  }

  @Test
  @DisplayName("매핑 없는 유형은 재시도 예산을 쓰지 않고 즉시 실패로 확정한다")
  void failsFastOnUnmappedResourceType() {
    given(jobRepository.claim(anyInt())).willReturn(List.of(job(1L, 0)));
    willThrow(new StorageDeletionRouter.UnmappedResourceTypeException("REPORT_PDF"))
        .given(router)
        .delete(any());

    worker.deletePendingObjects();

    then(jobRepository).should().markFailed(1L, StorageDeletionRouter.UNMAPPED_RESOURCE_TYPE);
    then(jobRepository).should(never()).markRetry(anyLong(), anyString());
  }

  @Test
  @DisplayName("한 건이 실패해도 배치의 나머지를 계속 처리한다")
  void continuesAfterIndividualFailure() {
    given(jobRepository.claim(anyInt())).willReturn(List.of(job(1L, 0), job(2L, 0), job(3L, 0)));
    // 특정 인자만 스텁하면 strict stubs 가 나머지 호출에 PotentialStubbingProblem 을 던지고,
    // 워커가 그걸 일반 실패로 잡아 1·3번까지 재시도로 떨어진다. any() 로 받아 안에서 갈라준다.
    willAnswer(
            invocation -> {
              StorageDeletionJob target = invocation.getArgument(0);
              if (target.id() == 2L) {
                throw new IllegalStateException("boom");
              }
              return null;
            })
        .given(router)
        .delete(any());

    worker.deletePendingObjects();

    // 실패한 2번을 건너뛰고 1·3번은 완료돼야 한다.
    // 배치가 통째로 멈추면 그 뒤의 아동 파일이 전부 안 지워진다.
    then(jobRepository).should().markCompleted(1L);
    then(jobRepository).should().markCompleted(3L);
    then(jobRepository).should().markRetry(eq(2L), anyString());
  }

  @Test
  @DisplayName("매 실행마다 선점된 채 방치된 잡을 회수한다")
  void releasesStuckJobsEveryRun() {
    given(jobRepository.claim(anyInt())).willReturn(List.of());

    worker.deletePendingObjects();

    then(jobRepository).should().releaseStuck(600L);
  }

  @Test
  @DisplayName("대기 중인 잡이 없으면 저장소를 부르지 않는다")
  void doesNothingWhenQueueEmpty() {
    given(jobRepository.claim(anyInt())).willReturn(List.of());

    worker.deletePendingObjects();

    then(router).shouldHaveNoInteractions();
  }
}
