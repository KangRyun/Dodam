package com.ssafy.b209.notification.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDateTime;

/**
 * NOTI-01 등록·갱신 결과다.
 *
 * <p>Token 원문·암호문·hash는 포함하지 않는다. 클라이언트는 자기가 보낸 Token을 이미 알고 있고, 응답에 실으면 로그·프록시에 남을 경로만 늘어난다.
 *
 * @param deviceId 등록한 설치 식별자
 * @param platform 저장된 기기 Platform
 * @param pushProvider 저장된 Push Provider
 * @param active 발송 대상 여부
 * @param registered 새로 등록했으면 {@code true}, 기존 기기를 갱신했으면 {@code false}
 * @param updatedAt 서버가 기록한 반영 시각
 */
@Schema(description = "푸시 디바이스 Token 등록 결과")
public record DeviceTokenResponse(
    String deviceId,
    String platform,
    String pushProvider,
    boolean active,
    boolean registered,
    LocalDateTime updatedAt) {}
