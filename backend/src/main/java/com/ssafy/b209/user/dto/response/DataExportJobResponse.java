package com.ssafy.b209.user.dto.response;

import com.ssafy.b209.user.domain.DataExportJob;
import com.ssafy.b209.user.domain.DataExportStatus;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDateTime;

/** 데이터 내보내기 요청이 접수된 작업의 공개 상태다. */
@Schema(description = "데이터 내보내기 작업 접수 상태")
public record DataExportJobResponse(
    @Schema(description = "데이터 내보내기 작업 ID", example = "901") Long dataExportJobId,
    @Schema(
            description = "내보내기 작업 상태",
            example = "PENDING",
            allowableValues = {"PENDING", "PROCESSING", "COMPLETED", "FAILED", "EXPIRED"})
        DataExportStatus exportStatus,
    @Schema(description = "작업 접수 시각", example = "2026-07-31T10:25:03") LocalDateTime requestedAt) {

  /**
   * 영속화된 작업을 생성 응답으로 변환한다.
   *
   * @param job 데이터 내보내기 작업
   * @return 공개 가능한 작업 식별자·상태·접수 시각
   */
  public static DataExportJobResponse from(DataExportJob job) {
    return new DataExportJobResponse(job.getId(), job.getExportStatus(), job.getCreatedAt());
  }
}
