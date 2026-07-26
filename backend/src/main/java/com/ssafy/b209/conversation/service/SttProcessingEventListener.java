package com.ssafy.b209.conversation.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 음성 답변 업로드 Transaction이 커밋된 뒤 STT 처리를 시작한다.
 *
 * <p>커밋 후 별도 Thread에서 실행하므로 업로드 201 응답은 STT 소요 시간을 기다리지 않는다. 처리 결과는 290 상태 조회로 확인한다.
 *
 * <p>여기서 발생한 예외는 흡수한다. AI 오류는 {@link SttProcessingService}가 FAILED로 종결하고, 선점 이전 단계에서 실패한 메시지는
 * PENDING으로 남아 {@link SttPendingRecoveryScheduler}가 회수한다.
 *
 * <p>{@code app.stt.trigger.enabled=false}로 끄면 업로드는 계속 PENDING만 남긴다. 내부 STT가 장애일 때 호출을 멈추기 위한 개폐
 * 장치이며, 이 경우 회수 작업도 함께 꺼야 재시도가 반복되지 않는다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.stt.trigger",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = true)
public class SttProcessingEventListener {

  private static final Logger log = LoggerFactory.getLogger(SttProcessingEventListener.class);

  private final SttProcessingService sttProcessingService;

  /**
   * STT 처리 오케스트레이터를 주입받는다.
   *
   * @param sttProcessingService PENDING 선점부터 결과 저장까지 담당하는 289 서비스
   */
  public SttProcessingEventListener(SttProcessingService sttProcessingService) {
    this.sttProcessingService = sttProcessingService;
  }

  /**
   * 업로드 커밋 후 해당 음성 답변 하나를 STT 처리한다.
   *
   * @param event STT 대상 메시지 식별자를 담은 이벤트
   */
  @Async("sttTaskExecutor")
  @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
  public void onVoiceAnswerStored(VoiceAnswerStoredEvent event) {
    Long messageId = event.conversationMessageId();
    try {
      sttProcessingService.process(messageId);
    } catch (RuntimeException exception) {
      log.warn(
          "음성 답변 STT 트리거가 실패해 PENDING으로 남깁니다. messageId={}, reason={}",
          messageId,
          exception.getClass().getSimpleName());
    }
  }
}
