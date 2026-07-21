package com.ssafy.b209.global.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Profile별 {@link CorsProperties}가 제공하는 허용 Origin으로 {@code /api/v1/**} MVC 요청의 CORS 정책을 구성한다.
 *
 * <p>CORS는 브라우저의 Cross-Origin 접근 제어일 뿐이며 인증과 인가를 대체하지 않는다.
 */
@Configuration
@EnableConfigurationProperties(CorsProperties.class)
public class CorsConfig implements WebMvcConfigurer {

  private final CorsProperties corsProperties;

  /**
   * Profile별 CORS Origin 설정을 주입한다.
   *
   * @param corsProperties 정규화된 허용 Origin 목록을 제공하는 설정 값
   */
  public CorsConfig(CorsProperties corsProperties) {
    this.corsProperties = corsProperties;
  }

  /**
   * {@code /api/v1/**} MVC 요청에 Profile별 Origin과 고정된 Method·Header·Credential 정책을 등록한다.
   *
   * @param registry CORS 매핑을 등록할 Spring MVC 레지스트리
   */
  @Override
  public void addCorsMappings(CorsRegistry registry) {
    registry
        .addMapping("/api/v1/**")
        .allowedOrigins(corsProperties.allowedOrigins().toArray(String[]::new))
        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
        .allowedHeaders("Content-Type", "Accept", "Authorization")
        .allowCredentials(false)
        .maxAge(3600);
  }
}
