package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.QuestionTtsMessage;
import java.math.BigDecimal;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** CONV-04 질문 TTS 음성 상태 선점과 결과 저장을 원자 조건으로 수행하는 저장소다. */
public interface QuestionTtsMessageRepository extends JpaRepository<QuestionTtsMessage, Long> {

  /**
   * 같은 음색·속도·말투 프로필의 성공 캐시가 없을 때만 AI 질문 하나를 PROCESSING으로 선점한다.
   *
   * <p>질문 행은 생성 시 {@code speech_status}가 비어 있으므로 {@code NULL}·{@code NOT_REQUIRED}·{@code
   * FAILED}에서만 선점을 허용해 재시도를 지원하고, {@code PROCESSING}·{@code SUCCESS}는 재선점하지 않는다.
   *
   * @param messageId TTS 대상 AI 질문 메시지 ID
   * @return 상태를 실제 변경한 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
      "update QuestionTtsMessage message set message.speechStatus = 'PROCESSING', "
          + "message.ttsVoice = :voice, message.ttsSpeed = :speed, "
          + "message.ttsToneProfile = :toneProfile "
          + "where message.id = :messageId and message.senderType = 'AI' "
          + "and message.messageType = 'QUESTION' "
          + "and (message.speechStatus is null or message.speechStatus in ('NOT_REQUIRED', 'FAILED') "
          + "or (message.speechStatus = 'SUCCESS' "
          + "and (message.ttsVoice is null or message.ttsVoice <> :voice "
          + "or message.ttsSpeed is null or message.ttsSpeed <> :speed "
          + "or message.ttsToneProfile is null or message.ttsToneProfile <> :toneProfile)))")
  int claimForSynthesis(
      @Param("messageId") Long messageId,
      @Param("voice") String voice,
      @Param("speed") BigDecimal speed,
      @Param("toneProfile") String toneProfile);

  /**
   * 현재 worker가 선점한 PROCESSING 질문에 성공 음성 결과만 반영한다.
   *
   * @param messageId TTS 대상 메시지 ID
   * @param storageKey 승격된 음성의 Root-relative 저장 key
   * @param audioUrl 재생 프록시 상대 경로
   * @param voice 이번 합성에 사용한 서비스 음성 코드
   * @param speed 이번 합성에 사용한 재생 속도
   * @return 상태가 PROCESSING이어서 실제 갱신된 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
      "update QuestionTtsMessage message set message.speechStatus = 'SUCCESS', "
          + "message.audioStorageKey = :storageKey, message.audioUrl = :audioUrl "
          + "where message.id = :messageId and message.speechStatus = 'PROCESSING' "
          + "and message.ttsVoice = :voice and message.ttsSpeed = :speed "
          + "and message.ttsToneProfile = :toneProfile")
  int completeSuccess(
      @Param("messageId") Long messageId,
      @Param("storageKey") String storageKey,
      @Param("audioUrl") String audioUrl,
      @Param("voice") String voice,
      @Param("speed") BigDecimal speed,
      @Param("toneProfile") String toneProfile);

  /**
   * 현재 worker가 선점한 PROCESSING 질문을 실패 상태로 끝낸다.
   *
   * @param messageId TTS 대상 메시지 ID
   * @return 상태가 PROCESSING이어서 실제 갱신된 행 수
   */
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(
          "update QuestionTtsMessage message set message.speechStatus = 'FAILED' "
          + "where message.id = :messageId and message.speechStatus = 'PROCESSING' "
          + "and message.ttsVoice = :voice and message.ttsSpeed = :speed "
          + "and message.ttsToneProfile = :toneProfile")
  int markFailed(
      @Param("messageId") Long messageId,
      @Param("voice") String voice,
      @Param("speed") BigDecimal speed,
      @Param("toneProfile") String toneProfile);
}
