package com.ssafy.b209.user.dto.response;

import com.ssafy.b209.user.domain.DataExportJob;
import com.ssafy.b209.user.domain.DataExportStatus;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDateTime;

/**
 * 데이터 내보내기 작업 상태 조회에 공개하는 안전한 상태 정보다.
 *
 * @param dataExportJobId 데이터 내보내기 작업 식별자
 * @param exportStatus 현재 내보내기 작업 상태
 * @param requestedAt 작업 접수 시각
 * @param completedAt 작업 완료 시각
 * @param expiresAt 다운로드 만료 시각
 * @param failureCode 작업 실패 코드
 */
@Schema(description = "데이터 내보내기 작업 상태")
public record DataExportJobStatusResponse(
    @Schema(description = "데이터 내보내기 작업 ID", example = "901") Long dataExportJobId,
    @Schema(
            description = "내보내기 작업 상태",
            example = "COMPLETED",
            allowableValues = {"PENDING", "PROCESSING", "COMPLETED", "FAILED", "EXPIRED"})
        DataExportStatus exportStatus,
    @Schema(description = "작업 접수 시각", example = "2026-07-31T10:25:03") LocalDateTime requestedAt,
    @Schema(description = "작업 완료 시각", example = "2026-07-31T10:30:03", nullable = true)
        LocalDateTime completedAt,
    @Schema(description = "다운로드 만료 시각", example = "2026-08-01T10:30:03", nullable = true)
        LocalDateTime expiresAt,
    // ⚠️ 이름을 errorCode 로 되돌리지 말 것(S15P11B209-767). SwaggerEndpointTest 의
    //    INTERNAL_PROPERTIES 가드가 공개 스키마에서 그 이름을 전면 금지한다 — 예외 내부
    //    필드 유출을 이름으로 잡는 가드라, 업무 필드라도 같은 이름이면 걸린다.
    //    도메인(DataExportJob.errorCode)은 내부라 그대로다. 여기 응답 이름만 다르다.
    @Schema(description = "작업 실패 코드", example = "EXPORT_STORAGE_ERROR", nullable = true)
        String failureCode) {

  /**
   * 영속화된 작업을 상태 조회 응답으로 변환한다.
   *
   * @param job 데이터 내보내기 작업
   * @return 공개 가능한 작업 상태와 시각·실패 코드
   */
  public static DataExportJobStatusResponse from(DataExportJob job) {
    return new DataExportJobStatusResponse(
        job.getId(),
        job.getExportStatus(),
        job.getCreatedAt(),
        job.getCompletedAt(),
        job.getExpiresAt(),
        job.getErrorCode());
  }
}
