package com.ssafy.b209.infrastructure.ai.observation;

import jakarta.validation.Validator;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 외부 설정에 따라 관찰 리포트 생성 Client 구현을 선택한다.
 *
 * <p>현재는 Mock 구현만 제공하며 기본값도 Mock이다. 실제 AI 서버 연동({@code mode=http})은 동일 {@link AiObservationClient}
 * 경계 뒤에서 후속 이슈가 추가한다.
 */
@Configuration(proxyBeanMethods = false)
public class AiObservationClientConfig {

  /**
   * 외부 네트워크를 사용하지 않는 개발용 관찰 리포트 생성 Client를 생성한다.
   *
   * @param validator 관찰 생성 요청 계약 검증기
   * @return 결정적인 결과를 반환하는 Mock 관찰 리포트 생성 Client
   */
  @Bean
  @ConditionalOnProperty(
      prefix = "app.ai.observation",
      name = "mode",
      havingValue = "mock",
      matchIfMissing = true)
  public AiObservationClient mockAiObservationClient(Validator validator) {
    return new MockAiObservationClient(validator);
  }
}
