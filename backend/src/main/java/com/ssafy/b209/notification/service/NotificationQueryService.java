package com.ssafy.b209.notification.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.domain.NotificationAttribute;
import com.ssafy.b209.notification.dto.response.NotificationListItemResponse;
import com.ssafy.b209.notification.dto.response.NotificationListPageResponse;
import com.ssafy.b209.notification.repository.NotificationAttributeRepository;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * NOTI-03 알림 목록 조회 Use Case다.
 *
 * <p>이동 경로는 서버가 임의 URL을 만들지 않고 관련 자원 유형·식별자로 제공한다(명세 15.3). 부가 속성은 현재 페이지의 알림 ID를 모아 한 번에 조회해 항목별
 * 질의가 늘어나지 않게 한다.
 */
@Service
public class NotificationQueryService {

  private static final int MAX_PAGE_SIZE = 100;
  private static final Set<String> ALLOWED_TYPES =
      Set.of(
          "ANALYSIS_COMPLETED",
          "ANALYSIS_FAILED",
          "REPORT_COMPLETED",
          "NEW_EXPERT_POST",
          "COMMENT_CREATED",
          "CONSENT_UPDATED",
          "RETENTION_NOTICE",
          "ACTIVITY_REMINDER",
          "RISK_REVIEW_GUIDE");

  private final NotificationRepository notificationRepository;
  private final NotificationAttributeRepository attributeRepository;

  /**
   * 알림과 부가 속성 저장소를 연결한다.
   *
   * @param notificationRepository 수신자 알림 조회 저장소
   * @param attributeRepository 부가 속성 일괄 조회 저장소
   */
  public NotificationQueryService(
      NotificationRepository notificationRepository,
      NotificationAttributeRepository attributeRepository) {
    this.notificationRepository = notificationRepository;
    this.attributeRepository = attributeRepository;
  }

  /**
   * 수신자의 알림 목록을 최신순으로 조회한다.
   *
   * @param recipientUserId 인증된 수신자 사용자 ID
   * @param type 조회할 알림 유형이며 전체 조회는 {@code null}
   * @param unreadOnly 미열람만 조회할지 여부
   * @param page 0부터 시작하는 페이지
   * @param size 1 이상 100 이하 페이지 크기
   * @return 공통 페이지 형식의 알림 목록이며 결과가 없으면 빈 {@code content}
   * @throws BusinessException 유형 어휘가 DB 제약과 다르거나 페이지 값이 범위를 벗어난 경우
   */
  @Transactional(readOnly = true)
  public NotificationListPageResponse getNotifications(
      Long recipientUserId, String type, boolean unreadOnly, int page, int size) {
    String normalizedType = normalizeType(type);
    validatePageRequest(page, size);

    Page<Notification> found =
        notificationRepository.findInbox(
            recipientUserId,
            normalizedType,
            unreadOnly,
            PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "createdAt", "id")));

    Map<Long, Map<String, String>> attributes = loadAttributes(found.getContent());
    List<NotificationListItemResponse> content =
        found.getContent().stream()
            .map(
                notification ->
                    toItem(notification, attributes.getOrDefault(notification.getId(), Map.of())))
            .toList();

    return new NotificationListPageResponse(
        content,
        found.getNumber(),
        found.getSize(),
        found.getTotalElements(),
        found.getTotalPages(),
        found.isFirst(),
        found.isLast(),
        found.hasNext());
  }

  private Map<Long, Map<String, String>> loadAttributes(List<Notification> notifications) {
    if (notifications.isEmpty()) {
      return Map.of();
    }
    List<Long> ids = notifications.stream().map(Notification::getId).toList();
    return attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(ids).stream()
        .collect(
            Collectors.groupingBy(
                NotificationAttribute::getNotificationId,
                LinkedHashMap::new,
                Collectors.toMap(
                    NotificationAttribute::getAttributeKey,
                    NotificationAttribute::getValueText,
                    (first, second) -> first,
                    LinkedHashMap::new)));
  }

  private NotificationListItemResponse toItem(Notification notification, Map<String, String> data) {
    String resourceType = null;
    Long resourceId = null;
    if (notification.getRelatedReportId() != null) {
      resourceType = "REPORT";
      resourceId = notification.getRelatedReportId();
    } else if (notification.getRelatedDrawingSessionId() != null) {
      resourceType = "DRAWING_SESSION";
      resourceId = notification.getRelatedDrawingSessionId();
    } else if (notification.getRelatedPostId() != null) {
      resourceType = "POST";
      resourceId = notification.getRelatedPostId();
    }
    return new NotificationListItemResponse(
        notification.getId(),
        notification.getNotificationType(),
        notification.getTitle(),
        notification.getContent(),
        resourceType,
        resourceId,
        data,
        notification.getDeliveryStatus(),
        notification.getReadAt(),
        notification.getSentAt(),
        notification.getCreatedAt());
  }

  private String normalizeType(String type) {
    if (type == null || type.isBlank()) {
      return null;
    }
    String normalized = type.trim();
    if (!ALLOWED_TYPES.contains(normalized)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    return normalized;
  }

  private void validatePageRequest(int page, int size) {
    if (page < 0 || size < 1 || size > MAX_PAGE_SIZE) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }
}
