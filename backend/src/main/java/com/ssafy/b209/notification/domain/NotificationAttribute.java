package com.ssafy.b209.notification.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * 알림의 부가 속성 한 쌍이다. 명세 15.3 응답의 {@code data}를 구성한다.
 *
 * <p>V3가 {@code notifications.data_json}을 이 테이블로 정규화했다. 위험 관련 알림의 raw risk score는 저장하지 않는다(명세
 * 15.4).
 */
@Entity
@Table(name = "notification_attributes")
public class NotificationAttribute {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "notification_id", nullable = false)
  private Long notificationId;

  @Column(name = "attribute_key", nullable = false, length = 80)
  private String attributeKey;

  @Column(name = "value_type", nullable = false, length = 20)
  private String valueType;

  @Column(name = "value_text", nullable = false, length = 1000)
  private String valueText;

  protected NotificationAttribute() {}

  public Long getId() {
    return id;
  }

  public Long getNotificationId() {
    return notificationId;
  }

  public String getAttributeKey() {
    return attributeKey;
  }

  public String getValueType() {
    return valueType;
  }

  public String getValueText() {
    return valueText;
  }
}
