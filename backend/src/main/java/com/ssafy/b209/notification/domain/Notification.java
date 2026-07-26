package com.ssafy.b209.notification.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * 보호자에게 전달되는 알림 한 건이다.
 *
 * <p>이동 경로는 임의 URL 대신 관련 자원 ID 세 컬럼 중 채워진 하나로 표현한다(명세 15.3). 부가 데이터는 이 Entity가 아니라 {@link
 * NotificationAttribute}가 보관한다. V1의 {@code data_json}은 V3에서 정규화되며 제거됐다.
 */
@Entity
@Table(name = "notifications")
public class Notification {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "recipient_user_id", nullable = false)
  private Long recipientUserId;

  @Column(name = "notification_type", nullable = false, length = 40)
  private String notificationType;

  @Column(name = "title", nullable = false, length = 200)
  private String title;

  @Column(name = "content", nullable = false)
  private String content;

  @Column(name = "related_post_id")
  private Long relatedPostId;

  @Column(name = "related_report_id")
  private Long relatedReportId;

  @Column(name = "related_drawing_session_id")
  private Long relatedDrawingSessionId;

  @Column(name = "delivery_status", nullable = false, length = 20)
  private String deliveryStatus;

  @Column(name = "read_at")
  private LocalDateTime readAt;

  @Column(name = "sent_at")
  private LocalDateTime sentAt;

  @Column(name = "failed_at")
  private LocalDateTime failedAt;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  protected Notification() {}

  /**
   * 아직 읽지 않은 알림에만 읽은 시각을 기록한다.
   *
   * <p>이미 읽은 알림은 시각을 덮어쓰지 않는다. 목록 재진입이나 재시도로 처음 읽은 시각이 바뀌면 안 된다.
   *
   * @param now 서버 기준 읽은 시각
   * @return 이번 호출로 상태가 바뀌었으면 {@code true}
   */
  public boolean markRead(LocalDateTime now) {
    if (readAt != null) {
      return false;
    }
    this.readAt = now;
    return true;
  }

  public Long getId() {
    return id;
  }

  public Long getRecipientUserId() {
    return recipientUserId;
  }

  public String getNotificationType() {
    return notificationType;
  }

  public String getTitle() {
    return title;
  }

  public String getContent() {
    return content;
  }

  public Long getRelatedPostId() {
    return relatedPostId;
  }

  public Long getRelatedReportId() {
    return relatedReportId;
  }

  public Long getRelatedDrawingSessionId() {
    return relatedDrawingSessionId;
  }

  public String getDeliveryStatus() {
    return deliveryStatus;
  }

  public LocalDateTime getReadAt() {
    return readAt;
  }

  public LocalDateTime getSentAt() {
    return sentAt;
  }

  public LocalDateTime getFailedAt() {
    return failedAt;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
