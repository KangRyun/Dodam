package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 리포트에 노출할 아동의 대표 발화 한 건을 반환한다.
 *
 * @param messageId 원본 답변 메시지 식별자이며 없으면 {@code null}
 * @param text 발화 Snapshot 문구이며 없으면 {@code null}
 * @param source 발화 출처이며 음성 인식은 {@code STT}, 그 외는 {@code TEXT}
 * @param sttNeedsConfirmation 음성 인식 결과에 보호자 확인이 필요한지 여부
 */
@Schema(description = "리포트 대표 발화")
public record ReportUtteranceResponse(
    Long messageId, String text, String source, boolean sttNeedsConfirmation) {}
