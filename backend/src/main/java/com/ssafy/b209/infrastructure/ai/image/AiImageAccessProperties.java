package com.ssafy.b209.infrastructure.ai.image;

import java.net.URI;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * AI 서버에 전달할 내부 이미지 URL의 Base URL과 일회성 Token 유효 시간을 제공한다.
 *
 * <p>Base URL은 외부 공개 주소가 아니라 Backend 컨테이너를 가리키는 내부 HTTP 주소여야 한다. Token은 분석 요청 직후에만 소비하도록 5분을 초과할 수
 * 없다.
 *
 * @param internalBaseUrl AI 컨테이너에서 Backend에 접근할 내부 Base URL
 * @param tokenTtl 일회성 Token 유효 시간
 */
@ConfigurationProperties(prefix = "app.ai.image-access")
public record AiImageAccessProperties(
    @DefaultValue("http://backend:8080") URI internalBaseUrl,
    @DefaultValue("60s") Duration tokenTtl) {

  private static final Duration MAX_TOKEN_TTL = Duration.ofMinutes(5);

  /** 내부 URL과 Token 유효 시간을 안전한 범위로 검증하고 Base URL 끝의 {@code /}를 제거한다. */
  public AiImageAccessProperties {
    if (internalBaseUrl == null
        || !internalBaseUrl.isAbsolute()
        || !"http".equalsIgnoreCase(internalBaseUrl.getScheme())
        || internalBaseUrl.getHost() == null
        || internalBaseUrl.getUserInfo() != null
        || internalBaseUrl.getQuery() != null
        || internalBaseUrl.getFragment() != null
        || (internalBaseUrl.getPath() != null
            && !internalBaseUrl.getPath().isBlank()
            && !"/".equals(internalBaseUrl.getPath()))) {
      throw new IllegalArgumentException("AI image access base URL must be an absolute HTTP URL");
    }
    if (tokenTtl == null
        || tokenTtl.isZero()
        || tokenTtl.isNegative()
        || tokenTtl.compareTo(MAX_TOKEN_TTL) > 0) {
      throw new IllegalArgumentException("AI image access token TTL must be between 1ms and 5m");
    }
    String normalized = internalBaseUrl.toString().replaceAll("/+$", "");
    internalBaseUrl = URI.create(normalized);
  }
}
