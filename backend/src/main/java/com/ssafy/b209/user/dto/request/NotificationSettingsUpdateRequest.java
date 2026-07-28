package com.ssafy.b209.user.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;

/**
 * 로그인 사용자가 본인의 알림 수신 설정을 변경하는 요청이다.
 *
 * <p>부분 변경이 아니라 전체 교체(upsert)이므로 네 필드를 모두 전달해야 하며, 하나라도 누락되면 {@link NotNull} 위반으로 400을 반환한다. 각 필드는
 * {@code boolean}이 아닌 {@code Boolean}으로 받아 누락(null)과 명시적 {@code false}를 구분한다.
 *
 * @param analysisCompleted 분석 완료 알림 수신 여부
 * @param community 커뮤니티 알림 수신 여부
 * @param serviceNotice 서비스 공지 수신 여부
 * @param marketing 마케팅 알림 수신 여부
 */
@Schema(description = "알림 수신 설정 변경 요청")
public record NotificationSettingsUpdateRequest(
    @Schema(description = "분석 완료 알림 수신 여부", example = "true") @NotNull Boolean analysisCompleted,
    @Schema(description = "커뮤니티 알림 수신 여부", example = "true") @NotNull Boolean community,
    @Schema(description = "서비스 공지 수신 여부", example = "true") @NotNull Boolean serviceNotice,
    @Schema(description = "마케팅 알림 수신 여부", example = "false") @NotNull Boolean marketing) {}
