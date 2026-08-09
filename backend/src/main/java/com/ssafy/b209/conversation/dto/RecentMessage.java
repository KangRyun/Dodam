package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * AI 질문 생성 요청에 포함하는 최소 대화 문맥이다.
 *
 * <p>선택형 답변은 화면 문구를 {@code text}로, 문구 변경과 무관한 식별값을 {@code selectedOptionCodes}로 함께 전달한다. 음성·텍스트
 * 답변에는 선택 코드가 없으므로 {@code selectedOptionCodes}는 {@code null}이다.
 *
 * @param messageId 저장된 대화 메시지 식별자
 * @param senderType 메시지 발신자 유형
 * @param messageType 저장된 메시지 유형
 * @param text 질문 원문, STT 결과 또는 선택한 옵션 Label
 * @param selectedOptionCodes 선택형 답변에서 선택한 옵션 Code 목록 또는 해당하지 않을 때 {@code null}
 */
@Schema(description = "AI 질문 생성에 사용하는 최근 대화 문맥")
public record RecentMessage(
    Long messageId,
    String senderType,
    String messageType,
    String text,
    @Schema(
            description = "선택형 답변의 옵션 Code 목록. 음성·텍스트 답변에서는 null",
            example = "[\"CHIP_NO\"]",
            nullable = true)
        List<String> selectedOptionCodes) {

  /**
   * 선택 답변 식별값이 없는 기존 문맥을 생성한다.
   *
   * @param messageId 저장된 대화 메시지 식별자
   * @param senderType 메시지 발신자 유형
   * @param messageType 저장된 메시지 유형
   * @param text 질문 또는 답변 문맥
   */
  public RecentMessage(Long messageId, String senderType, String messageType, String text) {
    this(messageId, senderType, messageType, text, null);
  }
}
