package com.ssafy.b209.conversation.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Instant;

/**
 * 음성 답변 multipart의 JSON metadata다.
 *
 * @param questionMessageId 답변이 연결될 같은 대화 세션의 질문 메시지 ID
 * @param clientStartedAt 클라이언트 녹음 시작 시각
 * @param clientEndedAt 클라이언트 녹음 종료 시각
 * @param stopReason 녹음을 끝낸 사유
 */
@JsonIgnoreProperties(ignoreUnknown = false)
public record VoiceAnswerMetadata(
    Long questionMessageId,
    Instant clientStartedAt,
    Instant clientEndedAt,
    VoiceAnswerStopReason stopReason) {

  /**
   * 파싱한 metadata의 필수값과 시간 순서를 검증한다.
   *
   * @throws BusinessException 필수값 누락·음수 ID·역전된 클라이언트 시각인 경우
   */
  public void validate() {
    if (questionMessageId == null
        || questionMessageId <= 0
        || clientStartedAt == null
        || clientEndedAt == null
        || stopReason == null
        || clientEndedAt.isBefore(clientStartedAt)) {
      throw new BusinessException(VoiceAnswerErrorCode.INVALID_METADATA);
    }
  }
}
