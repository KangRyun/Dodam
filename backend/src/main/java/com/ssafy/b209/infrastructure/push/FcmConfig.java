package com.ssafy.b209.infrastructure.push;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import java.io.FileInputStream;
import java.io.IOException;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Conditional;
import org.springframework.context.annotation.Configuration;

/**
 * FCM 발송이 가능한 환경에서만 {@code FirebaseApp}을 초기화하고 {@link FirebaseMessaging} Bean을 구성한다.
 *
 * <p>발송 스위치가 꺼져 있거나 자격증명을 쓸 수 없으면 이 Bean이 만들어지지 않으므로 애플리케이션은 정상 부팅한다. 초기화는 프로세스당 한 번만 수행하고 이미 초기화된
 * {@code FirebaseApp}이 있으면 재사용한다.
 *
 * <p>조건이 {@code enabled=true} 만 보던 시절에는, 스위치가 켜진 채 자격증명을 읽지 못하면 초기화 예외가 컨텍스트를 무너뜨려 서비스 전체가 중단됐다
 * (S15P11B209-681). 지금은 {@link FcmAvailableCondition}이 자격증명 접근 가능 여부까지 함께 판정한다.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(FcmProperties.class)
public class FcmConfig {

  /**
   * Service Account 자격증명으로 발송 전용 {@link FirebaseMessaging}를 만든다.
   *
   * @param properties 검증된 FCM 발송 설정
   * @return 발송에 사용할 {@link FirebaseMessaging}
   * @throws IOException 자격증명 파일을 읽지 못한 경우
   */
  @Bean
  @Conditional(FcmAvailableCondition.class)
  public FirebaseMessaging firebaseMessaging(FcmProperties properties) throws IOException {
    try (FileInputStream credentialsStream = new FileInputStream(properties.credentialsPath())) {
      GoogleCredentials credentials = GoogleCredentials.fromStream(credentialsStream);
      FirebaseOptions options = FirebaseOptions.builder().setCredentials(credentials).build();
      FirebaseApp app =
          FirebaseApp.getApps().isEmpty()
              ? FirebaseApp.initializeApp(options)
              : FirebaseApp.getInstance();
      return FirebaseMessaging.getInstance(app);
    }
  }
}
