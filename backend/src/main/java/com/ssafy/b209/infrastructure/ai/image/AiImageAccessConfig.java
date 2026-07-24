package com.ssafy.b209.infrastructure.ai.image;

import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisImageUrlProvider;
import com.ssafy.b209.storage.image.ImageStorage;
import java.security.SecureRandom;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.StringRedisTemplate;

/** HTTP 그림 분석 모드에서 일회성 내부 이미지 조회에 필요한 Bean을 구성한다. */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(AiImageAccessProperties.class)
@ConditionalOnProperty(prefix = "app.ai.drawing-analysis", name = "mode", havingValue = "http")
public class AiImageAccessConfig {

  /** Spring이 HTTP 그림 분석 mode의 이미지 접근 Bean을 구성할 때 사용하는 기본 생성자다. */
  public AiImageAccessConfig() {}

  /**
   * 암호학적으로 안전한 URL Token 생성기를 생성한다.
   *
   * @return 256-bit URL-safe Token 생성기
   */
  @Bean
  public AiImageAccessTokenGenerator aiImageAccessTokenGenerator() {
    return new SecureRandomAiImageAccessTokenGenerator(new SecureRandom());
  }

  /**
   * Redis 기반 일회성 Token 저장소를 생성한다.
   *
   * @param redisTemplate Redis 명령과 Lua 실행에 사용할 Template
   * @param tokenGenerator 불투명 Token 생성기
   * @return TTL과 원자적 소비를 지원하는 Token 저장소
   */
  @Bean
  public AiImageAccessTokenStore aiImageAccessTokenStore(
      StringRedisTemplate redisTemplate, AiImageAccessTokenGenerator tokenGenerator) {
    return new RedisAiImageAccessTokenStore(redisTemplate, tokenGenerator);
  }

  /**
   * Token 저장소와 이미지 Storage를 조합하는 Application Service를 생성한다.
   *
   * @param tokenStore 일회성 Token 저장소
   * @param imageStorage 이미지 조회 경계
   * @param properties 내부 URL과 TTL 설정
   * @return 일회성 이미지 URL Service
   */
  @Bean
  public AiImageAccessService aiImageAccessService(
      AiImageAccessTokenStore tokenStore,
      ImageStorage imageStorage,
      AiImageAccessProperties properties) {
    return new AiImageAccessService(tokenStore, imageStorage, properties);
  }

  /**
   * 그림 분석 Client가 Storage Key 대신 일회성 내부 URL을 사용하도록 Provider를 생성한다.
   *
   * @param service 일회성 이미지 URL Service
   * @return 그림 분석 이미지 URL Provider
   */
  @Bean
  public DrawingAnalysisImageUrlProvider drawingAnalysisImageUrlProvider(
      AiImageAccessService service) {
    return new RedisDrawingAnalysisImageUrlProvider(service);
  }
}
