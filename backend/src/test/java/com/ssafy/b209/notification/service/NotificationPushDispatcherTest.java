package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import com.ssafy.b209.notification.repository.NotificationDeviceTokenRepository;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class NotificationPushDispatcherTest {

  private static final CreatedNotification NOTIFICATION =
      new CreatedNotification(
          900L, 11L, "ANALYSIS_COMPLETED", "분석이 완료됐어요", "리포트를 확인해 보세요", "REPORT", 55L);

  @Mock private PushSender pushSender;
  @Mock private NotificationDeviceTokenRepository deviceTokenRepository;
  @Mock private DeviceTokenCipher cipher;
  @Mock private NotificationDeliveryService deliveryService;
  @Captor private ArgumentCaptor<PushMessage> messageCaptor;

  private NotificationPushDispatcher dispatcher() {
    return new NotificationPushDispatcher(
        pushSender, deviceTokenRepository, cipher, deliveryService);
  }

  @Test
  void skipsEntirelyWhenSenderDisabled() {
    given(pushSender.isEnabled()).willReturn(false);

    dispatcher().dispatch(NOTIFICATION);

    verifyNoInteractions(deviceTokenRepository, cipher, deliveryService);
  }

  @Test
  void skipsWhenCipherNotConfigured() {
    given(pushSender.isEnabled()).willReturn(true);
    given(cipher.isConfigured()).willReturn(false);

    dispatcher().dispatch(NOTIFICATION);

    verifyNoInteractions(deviceTokenRepository, deliveryService);
  }

  @Test
  void sendsDataOnlyPayloadAndMarksDelivered() {
    given(pushSender.isEnabled()).willReturn(true);
    given(cipher.isConfigured()).willReturn(true);
    given(deviceTokenRepository.findByUserIdAndActiveTrue(11L))
        .willReturn(List.of(token(1L, "cipher-a")));
    given(cipher.decrypt("cipher-a")).willReturn("plain-token-a");
    given(pushSender.send(any(PushMessage.class))).willReturn(PushSendOutcome.SENT);

    dispatcher().dispatch(NOTIFICATION);

    verify(pushSender).send(messageCaptor.capture());
    PushMessage message = messageCaptor.getValue();
    assertThat(message.token()).isEqualTo("plain-token-a");
    assertThat(message.data())
        .containsOnlyKeys(
            "notificationId",
            "type",
            "title",
            "content",
            "relatedResourceType",
            "relatedResourceId")
        .containsEntry("notificationId", "900")
        .containsEntry("type", "ANALYSIS_COMPLETED")
        .containsEntry("title", "분석이 완료됐어요")
        .containsEntry("content", "리포트를 확인해 보세요")
        .containsEntry("relatedResourceType", "REPORT")
        .containsEntry("relatedResourceId", "55");
    assertThat(message.data()).doesNotContainKey("notification");
    verify(deliveryService).markDelivered(900L, true);
    verify(deliveryService, never()).deactivateDeviceToken(anyLong());
  }

  @Test
  void deactivatesTokenOnInvalidOutcomeAndMarksFailed() {
    given(pushSender.isEnabled()).willReturn(true);
    given(cipher.isConfigured()).willReturn(true);
    given(deviceTokenRepository.findByUserIdAndActiveTrue(11L))
        .willReturn(List.of(token(7L, "cipher-dead")));
    given(cipher.decrypt("cipher-dead")).willReturn("plain-token-dead");
    given(pushSender.send(any(PushMessage.class))).willReturn(PushSendOutcome.TOKEN_INVALID);

    dispatcher().dispatch(NOTIFICATION);

    verify(deliveryService).deactivateDeviceToken(7L);
    verify(deliveryService).markDelivered(900L, false);
  }

  @Test
  void skipsSendingWhenNoActiveTokens() {
    given(pushSender.isEnabled()).willReturn(true);
    given(cipher.isConfigured()).willReturn(true);
    given(deviceTokenRepository.findByUserIdAndActiveTrue(11L)).willReturn(List.of());

    dispatcher().dispatch(NOTIFICATION);

    verify(pushSender, never()).send(any());
    verify(deliveryService, never()).markDelivered(anyLong(), anyBoolean());
  }

  @Test
  void skipsTokenThatFailsToDecryptWithoutMarkingDelivered() {
    given(pushSender.isEnabled()).willReturn(true);
    given(cipher.isConfigured()).willReturn(true);
    given(deviceTokenRepository.findByUserIdAndActiveTrue(11L))
        .willReturn(List.of(token(3L, "cipher-broken")));
    given(cipher.decrypt("cipher-broken")).willThrow(new IllegalStateException("broken"));

    dispatcher().dispatch(NOTIFICATION);

    verify(pushSender, never()).send(any());
    verify(deliveryService, never()).markDelivered(anyLong(), anyBoolean());
    verify(deliveryService, never()).deactivateDeviceToken(anyLong());
  }

  private NotificationDeviceToken token(long id, String ciphertext) {
    NotificationDeviceToken token =
        NotificationDeviceToken.register(
            11L,
            "device-" + id,
            ciphertext,
            "hashvalue0000000000000000000000000000000000000000000000000000000" + id,
            "ANDROID",
            "FCM",
            "1.0.0",
            LocalDateTime.of(2026, 7, 28, 9, 0));
    ReflectionTestUtils.setField(token, "id", id);
    return token;
  }
}
