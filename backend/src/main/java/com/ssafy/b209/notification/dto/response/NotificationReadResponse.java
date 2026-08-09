package com.ssafy.b209.notification.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * NOTI-04 단건 읽음 처리 결과다.
 *
 * <p>이미 읽은 알림을 다시 호출해도 최초 {@code readAt}을 그대로 반환한다. 클라이언트가 목록을 다시 받지 않고 배지를 갱신할 수 있게 시각을 함께 준다.
 *
 * <p>시각은 {@code Instant}로 담아 UTC ISO-8601(`Z` 접미사)로 직렬화한다.
 *
 * @param notificationId 처리한 알림 식별자
 * @param readAt 최초로 읽은 시각
 */
@Schema(description = "알림 읽음 처리 결과")
public record NotificationReadResponse(Long notificationId, Instant readAt) {}
