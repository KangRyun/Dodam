package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.SttVoiceAnswerMessage;
import java.math.BigDecimal;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 289 STT 상태 선점과 결과 저장을 원자 조건으로 수행하는 저장소다. */
public interface SttVoiceAnswerMessageRepository
    extends JpaRepository<SttVoiceAnswerMessage, Long> {

  /**
   * PENDING인 288 음성 답변만 PROCESSING으로 선점한다.
   *
   * @param messageId STT 대상 음성 답변 메시지 ID
   * @return 상태를 실제 변경한 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
      "update SttVoiceAnswerMessage message set message.speechStatus = 'PROCESSING' "
          + "where message.id = :messageId and message.speechStatus = 'PENDING' "
          + "and message.senderType = 'CHILD' and message.messageType = 'VOICE_ANSWER'")
  int claimPending(@Param("messageId") Long messageId);

  /**
   * 현재 worker가 선점한 PROCESSING 행에 성공 STT 결과만 반영한다.
   *
   * @param messageId STT 대상 메시지 ID
   * @param text 검증된 STT 원문
   * @param confidence DB DECIMAL(5,4)에 맞춘 신뢰도 또는 null
   * @param needsConfirmation 보호자 확인 필요 여부
   * @return 상태가 PROCESSING이어서 실제 갱신된 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
      "update SttVoiceAnswerMessage message set message.speechStatus = 'SUCCESS', "
          + "message.sttText = :text, message.sttConfidence = :confidence, "
          + "message.needsGuardianConfirmation = :needsConfirmation "
          + "where message.id = :messageId and message.speechStatus = 'PROCESSING'")
  int completeSuccess(
      @Param("messageId") Long messageId,
      @Param("text") String text,
      @Param("confidence") BigDecimal confidence,
      @Param("needsConfirmation") boolean needsConfirmation);

  /**
   * 현재 worker가 선점한 PROCESSING 행을 실패 상태로 끝낸다.
   *
   * @param messageId STT 대상 메시지 ID
   * @param needsConfirmation 실패 후 보호자 확인이 필요한지 여부
   * @return 상태가 PROCESSING이어서 실제 갱신된 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
      "update SttVoiceAnswerMessage message set message.speechStatus = 'FAILED', "
          + "message.sttText = null, message.sttConfidence = null, "
          + "message.needsGuardianConfirmation = :needsConfirmation "
          + "where message.id = :messageId and message.speechStatus = 'PROCESSING'")
  int completeFailure(
      @Param("messageId") Long messageId, @Param("needsConfirmation") boolean needsConfirmation);
}
