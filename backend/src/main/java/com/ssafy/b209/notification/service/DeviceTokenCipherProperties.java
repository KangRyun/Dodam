package com.ssafy.b209.notification.service;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Push 기기 Token을 저장할 때 사용하는 대칭키 설정이다.
 *
 * <p>키는 Base64로 인코딩한 32바이트(AES-256) 값이며 운영에서는 시크릿으로 주입한다. 비어 있으면 등록 API만 거부하고 애플리케이션은 정상 부팅한다. 기동을
 * 막으면 알림과 무관한 기능까지 함께 멈춘다.
 */
@Component
@ConfigurationProperties(prefix = "app.push.device-token")
public class DeviceTokenCipherProperties {
  private String encryptionKey = "";

  /**
   * @return Base64로 인코딩한 AES-256 키이며 미구성 시 빈 문자열
   */
  public String getEncryptionKey() {
    return encryptionKey;
  }

  public void setEncryptionKey(String encryptionKey) {
    this.encryptionKey = encryptionKey;
  }
}
