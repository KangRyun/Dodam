package com.ssafy.b209.notification.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.Map;

/**
 * NOTI-03 목록의 알림 한 건이다. 명세 15.3 항목 계약을 따른다.
 *
 * <p>시각은 {@code Instant}로 담아 UTC ISO-8601(`Z` 접미사)로 직렬화한다. 타임존 표기가 없으면 클라이언트가 값을 자기 지역 시각으로 해석해
 * UTC와의 차이만큼 어긋난다.
 *
 * @param notificationId 알림 식별자
 * @param type 알림 유형
 * @param title 알림 제목
 * @param content 알림 내용
 * @param relatedResourceType 이동 대상 자원 유형이며 없으면 {@code null}
 * @param relatedResourceId 이동 대상 자원 식별자이며 없으면 {@code null}
 * @param data 부가 속성 key-value이며 없으면 빈 Map
 * @param deliveryStatus 전송 상태
 * @param readAt 읽은 시각이며 미열람이면 {@code null}
 * @param sentAt 전송 시각이며 미전송이면 {@code null}
 * @param createdAt 생성 시각
 */
@Schema(description = "알림 목록 항목")
public record NotificationListItemResponse(
    Long notificationId,
    String type,
    String title,
    String content,
    String relatedResourceType,
    Long relatedResourceId,
    Map<String, String> data,
    String deliveryStatus,
    Instant readAt,
    Instant sentAt,
    Instant createdAt) {}
