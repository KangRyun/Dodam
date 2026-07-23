package com.ssafy.b209.conversation.service;

import com.ssafy.b209.infrastructure.ai.AiSttClient;
import com.ssafy.b209.infrastructure.ai.AiSttRequest;
import com.ssafy.b209.infrastructure.ai.AiSttResponse;
import com.ssafy.b209.storage.audio.OpenedAudio;
import com.ssafy.b209.storage.audio.StoredAudioReader;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * 288 PENDING 음성 답변을 내부 AI STT에 전달하고 결과 상태를 저장하는 289 오케스트레이터다.
 *
 * <p>외부 공개 Controller가 아닌 작업 실행 경계다. 업로드·파일 검증·파일 삭제·질문 순번 변경은 수행하지 않는다.
 */
@Service
public class SttProcessingService {
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
      return persistenceService.completeSuccess(
          claim.messageId(),
          response.text(),
          response.confidence(),
          claim.needsGuardianConfirmation());
    } catch (RuntimeException exception) {
      return persistenceService.completeFailure(
          claim.messageId(), claim.needsGuardianConfirmation());
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
