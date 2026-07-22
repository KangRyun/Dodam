package com.ssafy.b209.infrastructure.ai.drawing;

import jakarta.validation.Validator;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/** 그림 분석 AI Client 전용 HTTP 연결 설정과 Bean 구성을 담당한다. */
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
  public DrawingAnalysisClient drawingAnalysisClient(
      @Qualifier("drawingAnalysisRestClient") RestClient restClient,
      DrawingAnalysisClientProperties properties,
      Validator validator) {
    return new RestClientDrawingAnalysisClient(restClient, properties.endpointPath(), validator);
  }
}
