package com.ssafy.b209.infrastructure.ai.drawing;

import jakarta.validation.Validator;
import java.time.Clock;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/** 외부 설정에 따라 Mock 또는 HTTP 그림 분석 Client를 선택하고 필요한 Bean을 구성한다. */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(DrawingAnalysisClientProperties.class)
public class DrawingAnalysisClientConfig {

  /**
   * 외부 설정의 Base URL과 Timeout을 사용하는 그림 분석 전용 RestClient를 생성한다.
   *
   * <p>이 과정에서는 요청을 전송하거나 AI 서버 연결 여부를 확인하지 않는다.
   *
   * @param builder Spring Boot가 제공하는 RestClient Builder
   * @param properties 검증된 그림 분석 Client 연결 설정
   * @return 그림 분석 호출에만 사용하는 RestClient
   */
  @Bean("drawingAnalysisRestClient")
  @ConditionalOnProperty(prefix = "app.ai.drawing-analysis", name = "mode", havingValue = "http")
  public RestClient drawingAnalysisRestClient(
      RestClient.Builder builder, DrawingAnalysisClientProperties properties) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(properties.connectTimeout());
    requestFactory.setReadTimeout(properties.readTimeout());
    return builder.baseUrl(properties.baseUrl().toString()).requestFactory(requestFactory).build();
  }

  /**
   * 그림 분석 계약을 호출할 Application 경계 구현체를 생성한다.
   *
   * @param restClient 그림 분석 전용 RestClient
   * @param properties 검증된 그림 분석 Client 설정
   * @param validator 요청·응답 계약 검증기
   * @return RestClient 기반 그림 분석 Client
   */
  @Bean
  @ConditionalOnProperty(prefix = "app.ai.drawing-analysis", name = "mode", havingValue = "http")
  public DrawingAnalysisClient httpDrawingAnalysisClient(
      @Qualifier("drawingAnalysisRestClient") RestClient restClient,
      DrawingAnalysisClientProperties properties,
      Validator validator) {
    return new RestClientDrawingAnalysisClient(restClient, properties.endpointPath(), validator);
  }

  /**
   * 외부 네트워크를 사용하지 않는 개발용 그림 분석 Client를 생성한다.
   *
   * @param validator 그림 분석 요청 계약 검증기
   * @param clock Mock 응답 처리 시각을 생성하는 UTC Clock
   * @return 결정적인 결과를 반환하는 Mock 그림 분석 Client
   */
  @Bean
  @ConditionalOnProperty(prefix = "app.ai.drawing-analysis", name = "mode", havingValue = "mock")
  public DrawingAnalysisClient mockDrawingAnalysisClient(Validator validator, Clock clock) {
    return new MockDrawingAnalysisClient(validator, clock);
  }
}
