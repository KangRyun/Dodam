package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDateTime;

/**
 * 리포트 대상 그림 활동 세션의 요약 정보를 반환한다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param childId 소유 아동 식별자
 * @param drawingTypeCode 그림 활동 유형 코드
 * @param drawingTypeName 그림 활동 유형 표시명
 * @param title 그림 제목이며 없으면 {@code null}
 * @param inputMethod 입력 방식 코드
 * @param startedAt 활동 시작 시각
 * @param completedAt 활동 완료 시각이며 진행 중이면 {@code null}
 * @param durationMs 활동 소요 시간(ms)이며 완료 전이면 {@code null}
 */
@Schema(description = "리포트 그림 활동 세션 요약")
public record ReportDrawingSessionResponse(
    Long drawingSessionId,
    Long childId,
    String drawingTypeCode,
    String drawingTypeName,
    String title,
    String inputMethod,
    LocalDateTime startedAt,
    LocalDateTime completedAt,
    Long durationMs) {}
