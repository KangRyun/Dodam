package com.ssafy.b209.infrastructure.ai.drawing;

import java.net.URI;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 그림 분석 AI 서버 연결에 필요한 설정을 외부 환경에서 Binding한다.
 *
 * <p>Bean 생성 과정에서는 네트워크 연결을 시도하지 않으며 Base URL과 Timeout의 안전한 형식만 검증한다.
 *
 * @param baseUrl 그림 분석 AI 서버의 HTTP 또는 HTTPS Base URL
 * @param endpointPath 그림 분석 요청을 전송할 절대 Path
 * @param connectTimeout TCP 연결 제한 시간
 * @param readTimeout 응답을 기다리는 제한 시간
 */
@ConfigurationProperties(prefix = "app.ai.drawing-analysis")
public record DrawingAnalysisClientProperties(
    URI baseUrl, String endpointPath, Duration connectTimeout, Duration readTimeout) {

  /**
   * 외부 HTTP Client가 안전하게 사용할 수 있도록 연결 설정의 불변 조건을 검증한다.
   *
   * @param baseUrl 그림 분석 AI 서버의 HTTP 또는 HTTPS Base URL
   * @param endpointPath 그림 분석 요청을 전송할 절대 Path
   * @param connectTimeout TCP 연결 제한 시간
   * @param readTimeout 응답을 기다리는 제한 시간
   * @throws IllegalArgumentException URL·Path·Timeout이 안전한 연결 설정 조건을 충족하지 못하는 경우
   */
  public DrawingAnalysisClientProperties {
    if (baseUrl == null
        || !baseUrl.isAbsolute()
        || !("http".equalsIgnoreCase(baseUrl.getScheme())
            || "https".equalsIgnoreCase(baseUrl.getScheme()))
        || baseUrl.getHost() == null
        || baseUrl.getQuery() != null
        || baseUrl.getFragment() != null) {
      throw new IllegalArgumentException(
          "Drawing analysis base URL must be an HTTP or HTTPS absolute URI");
    }
    if (endpointPath == null
        || endpointPath.isBlank()
        || !endpointPath.startsWith("/")
        || endpointPath.startsWith("//")) {
      throw new IllegalArgumentException(
          "Drawing analysis endpoint path must start with one slash");
    }
    if (connectTimeout == null || connectTimeout.isZero() || connectTimeout.isNegative()) {
      throw new IllegalArgumentException("Drawing analysis connect timeout must be positive");
    }
    if (readTimeout == null || readTimeout.isZero() || readTimeout.isNegative()) {
      throw new IllegalArgumentException("Drawing analysis read timeout must be positive");
    }
  }
}
