package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.domain.NotificationAttribute;
import com.ssafy.b209.notification.dto.response.NotificationListItemResponse;
import com.ssafy.b209.notification.dto.response.NotificationListPageResponse;
import com.ssafy.b209.notification.repository.NotificationAttributeRepository;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.test.util.ReflectionTestUtils;

/** 목록 조회의 정렬·자원 매핑·부가 속성 조립과 Query 검증을 확인한다. */
@ExtendWith(MockitoExtension.class)
class NotificationQueryServiceTest {

  private static final Long USER_ID = 41L;

  @Mock private NotificationRepository notificationRepository;
  @Mock private NotificationAttributeRepository attributeRepository;

  @InjectMocks private NotificationQueryService service;

  @Test
  void returnsLatestFirstWithCommonPageMetadata() {
    Notification notification = notification(900L, 0L, 0L, 0L);
    given(notificationRepository.findInbox(eq(USER_ID), eq(null), eq(false), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(notification), PageRequest.of(0, 20), 1));
    given(attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(List.of(900L)))
        .willReturn(List.of());

    NotificationListPageResponse response = service.getNotifications(USER_ID, null, false, 0, 20);

    ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
    verify(notificationRepository)
        .findInbox(eq(USER_ID), eq(null), eq(false), pageableCaptor.capture());
    assertThat(pageableCaptor.getValue().getSort())
        .isEqualTo(Sort.by(Sort.Direction.DESC, "createdAt", "id"));
    assertThat(response.content()).hasSize(1);
    assertThat(response.page()).isZero();
    assertThat(response.size()).isEqualTo(20);
    assertThat(response.totalElements()).isEqualTo(1);
    assertThat(response.first()).isTrue();
    assertThat(response.last()).isTrue();
    assertThat(response.hasNext()).isFalse();
    assertThat(response.content().getFirst().data()).isEmpty();
  }

  @Test
  void exposesRelatedResourceInsteadOfServerBuiltUrl() {
    Notification reportNotification = notification(901L, null, 55L, 66L);
    given(notificationRepository.findInbox(any(), any(), anyBoolean(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(reportNotification), PageRequest.of(0, 20), 1));
    given(attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(List.of(901L)))
        .willReturn(List.of());

    NotificationListItemResponse item =
        service.getNotifications(USER_ID, null, false, 0, 20).content().getFirst();

    // 리포트가 채워져 있으면 리포트를 우선한다. 세 컬럼이 동시에 채워질 수 있어 우선순위를 고정한다.
    assertThat(item.relatedResourceType()).isEqualTo("REPORT");
    assertThat(item.relatedResourceId()).isEqualTo(55L);
  }

  @Test
  void leavesRelatedResourceEmptyWhenNoResourceIsLinked() {
    Notification plain = notification(902L, null, null, null);
    given(notificationRepository.findInbox(any(), any(), anyBoolean(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(plain), PageRequest.of(0, 20), 1));
    given(attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(List.of(902L)))
        .willReturn(List.of());

    NotificationListItemResponse item =
        service.getNotifications(USER_ID, null, false, 0, 20).content().getFirst();

    assertThat(item.relatedResourceType()).isNull();
    assertThat(item.relatedResourceId()).isNull();
  }

  @Test
  void buildsDataFromNormalizedAttributesInOneQuery() {
    Notification notification = notification(903L, null, null, 12L);
    given(notificationRepository.findInbox(any(), any(), anyBoolean(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(notification), PageRequest.of(0, 20), 1));
    given(attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(List.of(903L)))
        .willReturn(List.of(attribute(903L, "analysisId", "77"), attribute(903L, "childId", "3")));

    NotificationListItemResponse item =
        service.getNotifications(USER_ID, null, false, 0, 20).content().getFirst();

    assertThat(item.data()).containsExactly(entry("analysisId", "77"), entry("childId", "3"));
  }

  @Test
  void readsEntityWallClockAsUtcAndKeepsMissingTimesNull() {
    Notification notification = notification(904L, null, null, 12L);
    given(notificationRepository.findInbox(any(), any(), anyBoolean(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(notification), PageRequest.of(0, 20), 1));
    given(attributeRepository.findByNotificationIdInOrderByAttributeKeyAsc(List.of(904L)))
        .willReturn(List.of());

    NotificationListItemResponse item =
        service.getNotifications(USER_ID, null, false, 0, 20).content().getFirst();

    // Entity의 LocalDateTime은 앱 내부 규약상 UTC 벽시계다. KST로 해석하면 9시간 어긋난다.
    assertThat(item.createdAt()).isEqualTo(Instant.parse("2026-07-26T10:00:00Z"));
    // 미열람·미전송은 시각을 만들지 않고 null을 유지한다.
    assertThat(item.readAt()).isNull();
    assertThat(item.sentAt()).isNull();
  }

  @Test
  void skipsAttributeQueryForEmptyPage() {
    given(notificationRepository.findInbox(any(), any(), anyBoolean(), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(), PageRequest.of(0, 20), 0));

    NotificationListPageResponse response = service.getNotifications(USER_ID, null, false, 0, 20);

    assertThat(response.content()).isEmpty();
    assertThat(response.totalElements()).isZero();
    verify(attributeRepository, never()).findByNotificationIdInOrderByAttributeKeyAsc(any());
  }

  @Test
  void rejectsTypesOutsideTheDatabaseVocabularyAndPageValuesOutOfRange() {
    assertInvalid(() -> service.getNotifications(USER_ID, "UNKNOWN_TYPE", false, 0, 20));
    assertInvalid(() -> service.getNotifications(USER_ID, null, false, -1, 20));
    assertInvalid(() -> service.getNotifications(USER_ID, null, false, 0, 0));
    assertInvalid(() -> service.getNotifications(USER_ID, null, false, 0, 101));

    verify(notificationRepository, never()).findInbox(any(), any(), anyBoolean(), any());
  }

  @Test
  void treatsBlankTypeAsNoFilter() {
    given(notificationRepository.findInbox(eq(USER_ID), eq(null), eq(true), any(Pageable.class)))
        .willReturn(new PageImpl<>(List.of(), PageRequest.of(0, 20), 0));

    service.getNotifications(USER_ID, "  ", true, 0, 20);

    verify(notificationRepository).findInbox(eq(USER_ID), eq(null), eq(true), any(Pageable.class));
  }

  private java.util.Map.Entry<String, String> entry(String key, String value) {
    return java.util.Map.entry(key, value);
  }

  private Notification notification(Long id, Long postId, Long reportId, Long sessionId) {
    Notification notification = new Notification() {};
    ReflectionTestUtils.setField(notification, "id", id);
    ReflectionTestUtils.setField(notification, "recipientUserId", USER_ID);
    ReflectionTestUtils.setField(notification, "notificationType", "ANALYSIS_COMPLETED");
    ReflectionTestUtils.setField(notification, "title", "분석이 완료됐어요");
    ReflectionTestUtils.setField(notification, "content", "리포트를 확인해 보세요");
    ReflectionTestUtils.setField(notification, "relatedPostId", postId);
    ReflectionTestUtils.setField(notification, "relatedReportId", reportId);
    ReflectionTestUtils.setField(notification, "relatedDrawingSessionId", sessionId);
    ReflectionTestUtils.setField(notification, "deliveryStatus", "SENT");
    ReflectionTestUtils.setField(
        notification, "createdAt", LocalDateTime.parse("2026-07-26T10:00:00"));
    return notification;
  }

  private NotificationAttribute attribute(Long notificationId, String key, String value) {
    NotificationAttribute attribute = new NotificationAttribute() {};
    ReflectionTestUtils.setField(attribute, "notificationId", notificationId);
    ReflectionTestUtils.setField(attribute, "attributeKey", key);
    ReflectionTestUtils.setField(attribute, "valueType", "STRING");
    ReflectionTestUtils.setField(attribute, "valueText", value);
    return attribute;
  }

  private void assertInvalid(Runnable invocation) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommonErrorCode.INVALID_INPUT_VALUE));
  }
}
