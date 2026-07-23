package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 대화 활동의 집계 수치와 보호자용 요약을 반환한다.
 *
 * @param questionCount 대화 질문 수이며 미집계면 {@code null}
 * @param answeredCount 대화 응답 수이며 미집계면 {@code null}
 * @param skippedCount 건너뛴 질문 수이며 미집계면 {@code null}
 * @param summary 보호자용 대화 요약이며 없으면 {@code null}
 */
@Schema(description = "대화 요약")
public record ReportConversationSummaryResponse(
    Integer questionCount, Integer answeredCount, Integer skippedCount, String summary) {}
