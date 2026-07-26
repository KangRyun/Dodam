package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.repository.SttVoiceAnswerMessageRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * AFTER_COMMIT 이벤트가 유실돼 PENDING에 정체된 음성 답변을 주기적으로 회수한다.
 *
 * <p>이벤트 소비 Thread가 죽거나 애플리케이션이 커밋 직후 종료되면 STT가 시작되지 않아 290 폴링이 영구 PENDING을 보게 된다. 이 작업은 그 공백만 메우며,
 * 정상 경로의 트리거는 {@link SttProcessingEventListener}가 담당한다.
 *
 * <p>대상은 대화가 아직 CONVERSING인 메시지로 제한한다. 종료된 대화는 {@link SttProcessingPersistenceService#claim(Long)}이
 * 거부하므로 회수해도 상태가 바뀌지 않는다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.stt.recovery",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = true)
public class SttPendingRecoveryScheduler {

  private static final Logger log = LoggerFactory.getLogger(SttPendingRecoveryScheduler.class);

  private final SttVoiceAnswerMessageRepository messageRepository;
  private final SttProcessingService sttProcessingService;
  private final SttRecoveryProperties properties;
  private final Clock clock;

  /**
   * 정체 조회, STT 처리, 실행 조건, 시각 기준을 연결한다.
   *
   * @param messageRepository 정체된 PENDING 메시지를 조회하는 저장소
   * @param sttProcessingService 회수 대상을 실제로 처리하는 289 서비스
   * @param properties 정체 판단 경과 시간과 배치 크기
   * @param clock 업로드 시각과 동일한 UTC 기준 시계
   */
  public SttPendingRecoveryScheduler(
      SttVoiceAnswerMessageRepository messageRepository,
      SttProcessingService sttProcessingService,
      SttRecoveryProperties properties,
      Clock clock) {
    this.messageRepository = messageRepository;
    this.sttProcessingService = sttProcessingService;
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * 최소 경과 시간을 넘긴 PENDING 음성 답변을 배치 크기만큼 STT 처리한다.
   *
   * <p>개별 실패는 다음 실행에서 다시 시도하도록 흡수한다. 선점은 {@code claimPending()}이 원자적으로 수행하므로 이벤트 처리와 겹쳐도 AI를 두 번
   * 호출하지 않는다.
   */
  @Scheduled(fixedDelayString = "${app.stt.recovery.interval:60s}")
  public void recoverStalePendingVoiceAnswers() {
    LocalDateTime threshold =
        LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC).minus(properties.getMinimumAge());
    List<Long> messageIds =
        messageRepository.findStalePendingIds(
            threshold, PageRequest.of(0, properties.getBatchSize()));
    if (messageIds.isEmpty()) {
      return;
    }
    log.info("정체된 PENDING 음성 답변을 회수합니다. count={}", messageIds.size());
    for (Long messageId : messageIds) {
      try {
        sttProcessingService.process(messageId);
      } catch (RuntimeException exception) {
        log.warn(
            "PENDING 음성 답변 회수가 실패했습니다. messageId={}, reason={}",
            messageId,
            exception.getClass().getSimpleName());
      }
    }
  }
}
