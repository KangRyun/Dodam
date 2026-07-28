package com.ssafy.b209.infrastructure.push;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * FCM 발송 스위치와 Service Account 자격증명 경로를 외부 환경에서 Binding한다.
 *
 * <p>기본값은 발송 비활성이며, 활성화 시에만 {@code credentialsPath}로 {@code FirebaseApp}을 초기화한다. Bean 생성 과정에서는 파일을
 * 읽거나 네트워크를 사용하지 않는다.
 *
 * @param enabled FCM 발송 활성 여부
 * @param credentialsPath Service Account JSON 절대 경로
 */
@ConfigurationProperties(prefix = "app.push.fcm")
public record FcmProperties(boolean enabled, String credentialsPath) {}
