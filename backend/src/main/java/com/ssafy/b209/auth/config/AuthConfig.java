package com.ssafy.b209.auth.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.filter.AccessTokenAuthenticationFilter;
import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.service.OAuthProviderProperties;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.auth.token.JwtProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/** OAuth Provider와 서비스 JWT 발급에 필요한 외부 설정을 활성화한다. */
@Configuration
@EnableConfigurationProperties({
  OAuthProviderProperties.class,
  JwtProperties.class,
  AuthFilterProperties.class
})
public class AuthConfig {

  /** Spring이 인증 설정 Bean을 등록할 때 사용하는 생성자이다. */
  public AuthConfig() {}

  /**
   * Access JWT를 요청 Principal로 변환하는 Filter를 생성한다.
   *
   * @param decoder Access JWT Decoder
   * @param objectMapper 공통 오류 응답 직렬화 도구
   * @param properties Filter 전환 설정
   * @return API 요청에 적용할 Access Token Filter
   */
  @Bean
  public AccessTokenAuthenticationFilter accessTokenAuthenticationFilter(
      JwtAccessTokenDecoder decoder, ObjectMapper objectMapper, AuthFilterProperties properties) {
    return new AccessTokenAuthenticationFilter(decoder, objectMapper, properties);
  }

  /**
   * Access Token Filter를 모든 v1 API 경로의 앞단에 등록한다.
   *
   * @param filter 등록할 Access Token Filter
   * @return {@code /api/v1/*}에 한 번 적용되는 Filter 등록 정보
   */
  @Bean
  public FilterRegistrationBean<AccessTokenAuthenticationFilter>
      accessTokenAuthenticationFilterRegistration(AccessTokenAuthenticationFilter filter) {
    FilterRegistrationBean<AccessTokenAuthenticationFilter> registration =
        new FilterRegistrationBean<>(filter);
    registration.addUrlPatterns("/api/v1/*");
    registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 20);
    return registration;
  }
}
