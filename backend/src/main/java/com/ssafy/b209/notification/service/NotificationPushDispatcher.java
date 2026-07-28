package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import com.ssafy.b209.notification.repository.NotificationDeviceTokenRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 저장된 알림함 원본을 수신자의 활성 기기로 data-only 푸시 발송한다.
 *
 * <p>완료 Transaction 밖의 부수효과이므로 실패는 삼켜 로그만 남기고 완료·알림 생성 롤백으로 번지지 않게 한다(계약 §0-6·§0-7). 발송이 꺼져 있거나 암호화
 * 키가 없으면 아무것도 하지 않고 알림함 행은 {@code PENDING}으로 남긴다(§5.1).
 *
 * <p>페이로드는 {@code notification} 블록 없이 알림함 응답과 같은 필드명으로만 구성하고, Token 원문·본문은 로그에 남기지 않는다(§3·§5.4).
 */
@Component
public class NotificationPushDispatcher {

  private static final Logger log = LoggerFactory.getLogger(NotificationPushDispatcher.class);
  private static final int TOKEN_HASH_LOG_PREFIX = 8;

  private final PushSender pushSender;
  private final NotificationDeviceTokenRepository deviceTokenRepository;
  private final DeviceTokenCipher cipher;
  private final NotificationDeliveryService deliveryService;

  /**
   * 발송 경계, 기기 Token 저장소, 복호화 도구, 상태 반영 서비스를 연결한다.
   *
   * @param pushSender data-only 발송 경계
   * @param deviceTokenRepository 활성 기기 Token 조회 저장소
   * @param cipher Token 복호화 도구
   * @param deliveryService 전송 상태·죽은 Token 반영 서비스
   */
  public NotificationPushDispatcher(
      PushSender pushSender,
      NotificationDeviceTokenRepository deviceTokenRepository,
      DeviceTokenCipher cipher,
      NotificationDeliveryService deliveryService) {
    this.pushSender = pushSender;
    this.deviceTokenRepository = deviceTokenRepository;
    this.cipher = cipher;
    this.deliveryService = deliveryService;
  }

  /**
   * 알림 한 건을 수신자의 모든 활성 기기로 발송하고 결과를 반영한다.
   *
   * @param notification 발송할 알림함 원본 요약
   */
  public void dispatch(CreatedNotification notification) {
    if (!pushSender.isEnabled() || !cipher.isConfigured()) {
      return;
    }
    List<NotificationDeviceToken> tokens =
        deviceTokenRepository.findByUserIdAndActiveTrue(notification.recipientUserId());
    if (tokens.isEmpty()) {
      return;
    }
    Map<String, String> data = buildData(notification);
    boolean attempted = false;
    boolean anySent = false;
    for (NotificationDeviceToken token : tokens) {
      String plainToken;
      try {
        plainToken = cipher.decrypt(token.getTokenCiphertext());
      } catch (RuntimeException exception) {
        log.warn(
            "기기 Token 복호화 실패로 발송을 건너뜁니다. tokenHash={}, reason={}",
            tokenHashPrefix(token),
            exception.getClass().getSimpleName());
        continue;
      }
      attempted = true;
      PushSendOutcome outcome = pushSender.send(new PushMessage(plainToken, data));
      if (outcome == PushSendOutcome.SENT) {
        anySent = true;
      } else if (outcome == PushSendOutcome.TOKEN_INVALID) {
        deliveryService.deactivateDeviceToken(token.getId());
      }
    }
    if (attempted) {
      deliveryService.markDelivered(notification.notificationId(), anySent);
    }
  }

  private Map<String, String> buildData(CreatedNotification notification) {
    Map<String, String> data = new LinkedHashMap<>();
    data.put("notificationId", Long.toString(notification.notificationId()));
    data.put("type", notification.type());
    data.put("title", notification.title());
    data.put("content", notification.content());
    if (notification.relatedResourceType() != null && notification.relatedResourceId() != null) {
      data.put("relatedResourceType", notification.relatedResourceType());
      data.put("relatedResourceId", Long.toString(notification.relatedResourceId()));
    }
    return data;
  }

  private String tokenHashPrefix(NotificationDeviceToken token) {
    String tokenHash = token.getTokenHash();
    if (tokenHash == null) {
      return "unknown";
    }
    return tokenHash.substring(0, Math.min(TOKEN_HASH_LOG_PREFIX, tokenHash.length()));
  }
}
