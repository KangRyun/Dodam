package com.ssafy.b209.user.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * 로그인 사용자가 본인의 데이터 보관 정책을 변경하는 요청이다.
 *
 * <p>부분 변경이 아니라 전체 교체(upsert)이므로 두 필드를 모두 전달해야 한다. 보관 기간은 1일 이상, 사전 안내 시점은 0일 이상이어야 하며 안내 시점은 보관
 * 기간보다 짧아야 한다. 정책에서 확정하지 않은 최대 일수는 임의로 제한하지 않는다.
 *
 * @param retentionDays 데이터를 보관하는 기간(일)
 * @param noticeDaysBefore 보관 만료 며칠 전에 안내하는지(일)
 */
@Schema(description = "사용자 데이터 보관 정책 변경 요청")
public record DataRetentionPolicyUpdateRequest(
    @Schema(description = "데이터 보관 기간(일)", example = "365") @NotNull @Min(1) Integer retentionDays,
    @Schema(description = "보관 만료 사전 안내 시점(일)", example = "14") @NotNull @Min(0)
        Integer noticeDaysBefore) {

  /**
   * 사전 안내 시점이 보관 기간보다 앞서는지 확인한다.
   *
   * <p>필드 누락은 각 필드의 {@link NotNull}이 처리하므로 여기서는 두 값이 모두 있을 때만 관계를 검증한다.
   *
   * @return 필드가 누락됐거나 사전 안내 시점이 보관 기간보다 짧으면 {@code true}
   */
  @AssertTrue(message = "noticeDaysBefore는 retentionDays보다 작아야 합니다.")
  public boolean isNoticeBeforeRetentionValid() {
    return retentionDays == null || noticeDaysBefore == null || noticeDaysBefore < retentionDays;
  }
}
