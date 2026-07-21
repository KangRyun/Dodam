package com.ssafy.b209.global.config;

import java.net.URI;
import java.util.List;
import java.util.Objects;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * CORS Origin 허용 목록 설정이다.
 *
 * <p>각 배포 환경은 해당 환경에서 허용할 Origin 목록을 직접 제공해야 한다. 빈 목록은 Cross-Origin 접근을 허용하지 않으며, 정규화된 목록은 변경할 수 없는
 * 형태로 보관한다.
 *
 * @param allowedOrigins 환경별로 허용할 HTTP 또는 HTTPS Origin 목록
 */
@ConfigurationProperties(prefix = "app.cors")
public record CorsProperties(List<String> allowedOrigins) {

  /**
   * 전달된 목록을 CORS 정책에 사용할 수 있는 불변 Origin 목록으로 정규화한다.
   *
   * <p>{@code null}은 빈 목록으로 처리하고, 각 값의 공백을 제거한 뒤 빈 값과 {@code null} 값을 제외한다. 유효한 Origin만 허용하며 중복을
   * 제거한 불변 목록을 생성한다.
   *
   * @throws IllegalArgumentException 값이 HTTP 또는 HTTPS Origin이 아니거나, host·authority·port 형식이 올바르지
   *     않거나, 사용자 정보·경로·query·fragment를 포함하거나, wildcard {@code *}인 경우
   */
  public CorsProperties {
    allowedOrigins = normalize(allowedOrigins);
  }

  private static List<String> normalize(List<String> origins) {
    if (origins == null) {
      return List.of();
    }

    return origins.stream()
        .filter(Objects::nonNull)
        .map(String::trim)
        .filter(origin -> !origin.isEmpty())
        .peek(CorsProperties::validateOrigin)
        .distinct()
        .toList();
  }

  private static void validateOrigin(String origin) {
    URI uri;
    try {
      uri = URI.create(origin);
    } catch (IllegalArgumentException ignored) {
      throw new IllegalArgumentException("Invalid CORS origin");
    }

    boolean validScheme = "http".equals(uri.getScheme()) || "https".equals(uri.getScheme());
    int port = uri.getPort();
    String rawAuthority = uri.getRawAuthority();
    boolean validPort = rawAuthority != null && port <= 65535 && !rawAuthority.endsWith(":");
    boolean originOnly =
        uri.getHost() != null
            && uri.getUserInfo() == null
            && (uri.getRawPath() == null || uri.getRawPath().isEmpty())
            && uri.getRawQuery() == null
            && uri.getRawFragment() == null;
    if (!validScheme || !validPort || !originOnly || "*".equals(origin)) {
      throw new IllegalArgumentException("Invalid CORS origin");
    }
  }
}
