package com.ssafy.b209.conversation.service;

import com.ssafy.b209.infrastructure.ai.AiSttClient;
import com.ssafy.b209.infrastructure.ai.AiSttClientException;
import com.ssafy.b209.infrastructure.ai.AiSttRequest;
import com.ssafy.b209.infrastructure.ai.AiSttResponse;
import com.ssafy.b209.storage.audio.OpenedAudio;
import com.ssafy.b209.storage.audio.StoredAudioReader;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * 288 PENDING 음성 답변을 내부 AI STT에 전달하고 결과 상태를 저장하는 289 오케스트레이터다.
 *
 * <p>외부 공개 Controller가 아닌 작업 실행 경계다. 업로드·파일 검증·파일 삭제·질문 순번 변경은 수행하지 않는다.
 */
@Service
public class SttProcessingService {
  private static final Logger log = LoggerFactory.getLogger(SttProcessingService.class);

  private final SttProcessingPersistenceService persistenceService;
  private final StoredAudioReader audioReader;
  private final AiSttClient aiSttClient;

  /**
   * 상태 저장, 안전한 파일 읽기, 내부 AI 호출 경계를 연결한다.
   *
   * @param persistenceService PENDING 선점 및 결과 갱신 경계
   * @param audioReader 288 저장 파일을 읽기 전용으로 여는 경계
   * @param aiSttClient 최신 내부 STT multipart 호출 경계
   */
  public SttProcessingService(
      SttProcessingPersistenceService persistenceService,
      StoredAudioReader audioReader,
      AiSttClient aiSttClient) {
    this.persistenceService = persistenceService;
    this.audioReader = audioReader;
    this.aiSttClient = aiSttClient;
  }

  /**
   * 하나의 음성 답변을 중복 호출 없이 STT 처리한다.
   *
   * <p>이미 PROCESSING이면 AI를 다시 호출하지 않고 상태만 반환한다. SUCCESS·FAILED도 자동 재처리하지 않는다. AI 오류·schema 오류·파일 읽기
   * 오류는 STT 원문을 남기지 않은 FAILED 상태로 끝낸다.
   *
   * @param conversationMessageId 288이 생성한 VOICE_ANSWER 메시지 ID
   * @return 현재 또는 새로 저장한 STT 상태 결과
   */
  public SttProcessingResult process(Long conversationMessageId) {
    SttClaimResult claim = persistenceService.claim(conversationMessageId);
    return switch (claim.action()) {
      case PROCESSING -> existing(claim, SttProcessingResult.Status.PROCESSING);
      case SUCCESS -> existing(claim, SttProcessingResult.Status.SUCCESS);
      case FAILED -> existing(claim, SttProcessingResult.Status.FAILED);
      case CLAIMED -> processClaimed(claim);
    };
  }

  private SttProcessingResult processClaimed(SttClaimResult claim) {
    try {
      AiSttResponse response =
          aiSttClient.transcribe(new AiSttRequest(() -> open(claim), UUID.randomUUID().toString()));
      if (response.failed()) {
        // 무음·저신뢰는 장애가 아니라 정상적인 결과다. 텍스트를 저장하지 않고 FAILED로 끝내
        // 앱이 선택지를 띄우게 한다(정본 §19.6·§25). 저장하면 아이가 하지 않은 말이 남는다.
        logRejected(claim.messageId(), response.resolvedFailureReason());
        return persistenceService.completeFailure(
            claim.messageId(), claim.needsGuardianConfirmation());
      }
      return persistenceService.completeSuccess(
          claim.messageId(),
          response.text(),
          response.confidence(),
          // 보호자 확인은 한 번 필요해지면 내려가지 않는다 — 기존 값과 OR로 합친다.
          claim.needsGuardianConfirmation() || response.needsConfirmationOrDefault());
    } catch (RuntimeException exception) {
      logFailure(claim.messageId(), exception);
      return persistenceService.completeFailure(
          claim.messageId(), claim.needsGuardianConfirmation());
    }
  }

  /**
   * AI가 인식을 거절한 결과를 비민감 사유만으로 남긴다.
   *
   * <p>STT 원문은 기록하지 않는다. 사유 코드는 정본 §19.6 어휘이며, 상태 필드가 없는 구 AI 응답에서는 빈 텍스트를 뜻하는 {@code NO_SPEECH}로
   * 대체된다.
   */
  private void logRejected(Long messageId, String failureReason) {
    log.info("STT 인식 결과 미채택 messageId={} reason={}", messageId, failureReason);
  }

  /**
   * STT 실패 원인을 비민감 메타만으로 남긴다.
   *
   * <p>STT 원문·오디오·토큰·요청 ID나 예외 cause(내부 응답 본문이 담길 수 있음)는 남기지 않고, 오류 타입 또는 예외 클래스명과 messageId만 기록한다.
   */
  private void logFailure(Long messageId, RuntimeException exception) {
    if (exception instanceof AiSttClientException aiSttClientException) {
      log.warn("STT 처리 실패 messageId={} type={}", messageId, aiSttClientException.getType());
    } else {
      log.warn(
          "STT 처리 실패 messageId={} exception={}", messageId, exception.getClass().getSimpleName());
    }
  }

  private OpenedAudio open(SttClaimResult claim) {
    return audioReader.open(claim.audioStorageKey());
  }

  private SttProcessingResult existing(SttClaimResult claim, SttProcessingResult.Status status) {
    return new SttProcessingResult(
        claim.messageId(),
        status,
        claim.sttText(),
        claim.sttConfidence(),
        claim.needsGuardianConfirmation());
  }
}
