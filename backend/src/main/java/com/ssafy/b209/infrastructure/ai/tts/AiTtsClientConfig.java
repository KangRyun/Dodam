package com.ssafy.b209.infrastructure.ai.tts;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * 외부 설정에 따라 Mock 또는 HTTP 질문 TTS 합성 Client를 선택하고 필요한 Bean을 구성한다.
 *
 * <p>기본값은 Mock이며 실제 AI 서버 연동({@code mode=http})은 동일 {@link AiTtsClient} 경계 뒤에서 {@link
 * RestClientAiTtsClient}가 담당한다.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(AiTtsClientProperties.class)
public class AiTtsClientConfig {

  /**
   * 외부 설정의 Base URL과 Timeout을 사용하는 질문 TTS 합성 전용 RestClient를 생성한다.
   *
   * <p>이 과정에서는 요청을 전송하거나 AI 서버 연결 여부를 확인하지 않는다.
   *
   * @param builder Spring Boot가 제공하는 RestClient Builder
   * @param properties 검증된 합성 Client 연결 설정
   * @return 합성 호출에만 사용하는 RestClient
   */
  @Bean("ttsRestClient")
  @ConditionalOnProperty(prefix = "app.ai.tts", name = "mode", havingValue = "http")
  public RestClient ttsRestClient(RestClient.Builder builder, AiTtsClientProperties properties) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(properties.connectTimeout());
    requestFactory.setReadTimeout(properties.readTimeout());
    return builder.baseUrl(properties.baseUrl().toString()).requestFactory(requestFactory).build();
  }

  /**
   * 질문 TTS 합성 계약을 호출할 Application 경계 구현체를 생성한다.
   *
   * @param restClient 합성 전용 RestClient
   * @param properties 검증된 합성 Client 설정
   * @param internalToken BE↔AI 내부 계약 인증 토큰
   * @return RestClient 기반 합성 Client
   */
  @Bean
  @ConditionalOnProperty(prefix = "app.ai.tts", name = "mode", havingValue = "http")
  public AiTtsClient httpAiTtsClient(
      @Qualifier("ttsRestClient") RestClient restClient,
      AiTtsClientProperties properties,
      @Value("${AI_INTERNAL_TOKEN:}") String internalToken) {
    return new RestClientAiTtsClient(restClient, properties.endpointPath(), internalToken);
  }

  /**
   * 외부 네트워크를 사용하지 않는 개발용 질문 TTS 합성 Client를 생성한다.
   *
   * @return 재생 가능한 무음 MP3를 반환하는 Mock 합성 Client
   */
  @Bean
  @ConditionalOnProperty(
      prefix = "app.ai.tts",
      name = "mode",
      havingValue = "mock",
      matchIfMissing = true)
  public AiTtsClient mockAiTtsClient() {
    return new MockAiTtsClient();
  }
}
