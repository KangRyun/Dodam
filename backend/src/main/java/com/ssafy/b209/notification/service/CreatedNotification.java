package com.ssafy.b209.notification.service;

/**
 * 방금 저장된 알림함 원본 한 건을 발송에 필요한 최소 형태로 담는다.
 *
 * <p>푸시는 알림함의 사본이므로(계약 §0-4) 페이로드 필드는 저장된 행과 동일한 값을 그대로 싣는다. {@code relatedResourceType}·{@code
 * relatedResourceId}는 쌍으로 존재하거나 둘 다 {@code null}이며, 없으면 페이로드에 키를 넣지 않는다(§3).
 *
 * @param notificationId 저장된 알림 식별자
 * @param recipientUserId 수신자 사용자 ID
 * @param type 알림 유형
 * @param title 표시 제목
 * @param content 표시 본문
 * @param relatedResourceType 관련 자원 유형이며 없으면 {@code null}
 * @param relatedResourceId 관련 자원 식별자이며 없으면 {@code null}
 */
public record CreatedNotification(
    long notificationId,
    long recipientUserId,
    String type,
    String title,
    String content,
    String relatedResourceType,
    Long relatedResourceId) {}
