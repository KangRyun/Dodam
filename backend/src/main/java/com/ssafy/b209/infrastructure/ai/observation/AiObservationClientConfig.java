package com.ssafy.b209.infrastructure.ai.observation;

import jakarta.validation.Validator;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * 외부 설정에 따라 Mock 또는 HTTP 관찰 리포트 생성 Client를 선택하고 필요한 Bean을 구성한다.
 *
 * <p>기본값은 Mock이며 실제 AI 서버 연동({@code mode=http})은 동일 {@link AiObservationClient} 경계 뒤에서 {@link
 * RestClientAiObservationClient}가 담당한다.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(AiObservationClientProperties.class)
public class AiObservationClientConfig {

  /**
   * 외부 설정의 Base URL과 Timeout을 사용하는 관찰 리포트 생성 전용 RestClient를 생성한다.
   *
   * <p>이 과정에서는 요청을 전송하거나 AI 서버 연결 여부를 확인하지 않는다.
   *
   * @param builder Spring Boot가 제공하는 RestClient Builder
   * @param properties 검증된 관찰 리포트 생성 Client 연결 설정
   * @return 관찰 리포트 생성 호출에만 사용하는 RestClient
   */
  @Bean("observationRestClient")
  @ConditionalOnProperty(prefix = "app.ai.observation", name = "mode", havingValue = "http")
  public RestClient observationRestClient(
      RestClient.Builder builder, AiObservationClientProperties properties) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(properties.connectTimeout());
    requestFactory.setReadTimeout(properties.readTimeout());
    return builder.baseUrl(properties.baseUrl().toString()).requestFactory(requestFactory).build();
  }

  /**
   * 관찰 리포트 생성 계약을 호출할 Application 경계 구현체를 생성한다.
   *
   * @param restClient 관찰 리포트 생성 전용 RestClient
   * @param properties 검증된 관찰 리포트 생성 Client 설정
   * @param internalToken BE↔AI 내부 계약 인증 토큰
   * @param validator 요청·응답 계약 검증기
   * @return RestClient 기반 관찰 리포트 생성 Client
   */
  @Bean
  @ConditionalOnProperty(prefix = "app.ai.observation", name = "mode", havingValue = "http")
  public AiObservationClient httpAiObservationClient(
      @Qualifier("observationRestClient") RestClient restClient,
      AiObservationClientProperties properties,
      @Value("${AI_INTERNAL_TOKEN:}") String internalToken,
      Validator validator) {
    return new RestClientAiObservationClient(
        restClient, properties.endpointPath(), internalToken, validator);
  }

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
