package com.ssafy.b209.notification.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * NOTI-05 전체 읽음 처리 결과다.
 *
 * <p>이번 호출로 새로 읽음 처리된 건수와 그 값으로 기록한 읽은 시각을 준다. 클라이언트가 목록을 다시 받지 않고 미열람 배지를 갱신할 수 있게 한다. 이미 모두 읽어 바뀐
 * 건이 없으면 {@code updatedCount}는 0이고 {@code readAt}은 {@code null}이다.
 *
 * <p>시각은 {@code Instant}로 담아 UTC ISO-8601(`Z` 접미사)로 직렬화한다.
 *
 * @param updatedCount 이번 호출로 새로 읽음 처리된 알림 수
 * @param readAt 이번 호출로 기록한 읽은 시각이며 바뀐 건이 없으면 {@code null}
 */
@Schema(description = "알림 전체 읽음 처리 결과")
public record NotificationMarkAllReadResponse(int updatedCount, Instant readAt) {}
