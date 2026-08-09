package com.ssafy.b209.report.dto;

import com.ssafy.b209.report.domain.ReportStatus;
import java.time.LocalDateTime;

/**
 * 관찰 리포트 생성 작업의 현재 상태와 재시도 가능 여부를 전달한다.
 *
 * @param reportId 리포트 식별자
 * @param drawingSessionId 리포트가 속한 그림 활동 Session 식별자
 * @param analysisId 리포트 생성 근거인 최종 분석 식별자
 * @param reportVersion Session 안에서 증가하는 리포트 버전
 * @param reportStatus 현재 생성 상태
 * @param retryable 최신 FAILED 리포트여서 재생성할 수 있는지 여부
 * @param failureReason 개인정보를 포함하지 않는 실패 분류 코드
 * @param createdAt 리포트 생성 접수 시각
 * @param updatedAt 상태가 마지막으로 변경된 시각
 * @param failedAt 생성 실패 시각이며 실패하지 않았으면 {@code null}
 */
public record ReportGenerationStatusResponse(
    Long reportId,
    Long drawingSessionId,
    Long analysisId,
    int reportVersion,
    ReportStatus reportStatus,
    boolean retryable,
    String failureReason,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    LocalDateTime failedAt) {}
