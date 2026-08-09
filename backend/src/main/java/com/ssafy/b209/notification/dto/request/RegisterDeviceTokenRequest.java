package com.ssafy.b209.notification.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * NOTI-01 푸시 디바이스 Token 등록·갱신 요청이다. 명세 15.2 스키마를 따른다.
 *
 * <p>Bean Validation 제약을 두지 않는다. 값 누락·형식 오류를 모두 {@code DEVICE_TOKEN_INVALID} 하나로 응답해야 하므로 검증은 서비스가
 * 단독으로 수행한다.
 *
 * @param deviceId 클라이언트 설치 식별자이며 같은 값은 갱신으로 처리한다
 * @param platform {@code ANDROID}, {@code IOS}, {@code WEB} 중 하나
 * @param pushToken Push Provider가 발급한 Token 원문이며 저장 시 봉인한다
 * @param appVersion 등록 시점 앱 버전이며 선택 값이다
 */
@Schema(description = "푸시 디바이스 Token 등록 요청")
public record RegisterDeviceTokenRequest(
    @Schema(description = "클라이언트 설치 식별자", example = "installation-uuid") String deviceId,
    @Schema(description = "기기 Platform", example = "ANDROID") String platform,
    @Schema(description = "Push Provider Token 원문") String pushToken,
    @Schema(description = "앱 버전", example = "1.0.0") String appVersion) {}
