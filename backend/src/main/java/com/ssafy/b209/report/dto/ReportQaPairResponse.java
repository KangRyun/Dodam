package com.ssafy.b209.report.dto;

/**
 * 주제별 문답 한 쌍이다 (875 §6).
 *
 * <p>{@code sttNeedsConfirmation}이 {@code true}면 화면이 "음성 인식 내용을 확인해 주세요"를 함께 보여준다 — <strong>발화를 지우지
 * 않는다.</strong> 다만 그 발화는 근거와 대표 발화에서는 제외된다(계약 §4-4). 표시와 근거의 기준이 다르다.
 *
 * @param question AI 가 물은 질문
 * @param answer 아이 답변이며 없으면 {@code null}
 * @param state 답변 상태({@code ANSWERED}·{@code SKIPPED})
 * @param inputType 입력 방식({@code TEXT}·{@code VOICE})
 * @param sttNeedsConfirmation 음성 인식 확인이 필요한지 여부
 * @param isRepresentative 대표 문답인지 여부
 */
public record ReportQaPairResponse(
    String question,
    String answer,
    String state,
    String inputType,
    boolean sttNeedsConfirmation,
    boolean isRepresentative) {}
