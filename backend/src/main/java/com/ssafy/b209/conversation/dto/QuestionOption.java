package com.ssafy.b209.conversation.dto;

/**
 * 선택형 질문의 화면 표시용 선택지다.
 *
 * <p>{@code emoji}는 Template 폴백 선택지에만 존재한다. 내부 AI 계약의 선택지는 {@code code}와 {@code label}만 정의하므로 AI가
 * 생성한 질문에서는 {@code null}이다.
 *
 * @param code 선택지 식별자
 * @param label 표시 문구
 * @param emoji 표시 Emoji 또는 {@code null}
 */
public record QuestionOption(String code, String label, String emoji) {

  /**
   * Emoji가 없는 선택지를 만든다.
   *
   * @param code 선택지 식별자
   * @param label 표시 문구
   */
  public QuestionOption(String code, String label) {
    this(code, label, null);
  }
}
