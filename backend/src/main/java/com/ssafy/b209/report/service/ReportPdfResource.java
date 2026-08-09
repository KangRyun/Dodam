package com.ssafy.b209.report.service;

import java.io.IOException;
import java.io.InputStream;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 리포트 PDF 에 고정으로 들어가는 그림(감정 아이콘·마스코트)을 읽는다.
 *
 * <p>바뀌지 않는 리소스라 한 번 읽어 두고 계속 쓴다. 리포트마다 다시 읽으면 같은 바이트를 매번 Base64 로 바꾸게 된다.
 *
 * <p>못 읽으면 빈 값을 준다 — 장식 그림 한 장 때문에 내보내기 전체가 실패하면 보호자는 아무것도 받지 못한다. 실패도 기억해 두어 요청마다 같은 실패를 반복하지 않는다.
 */
abstract class ReportPdfResource {

  private static final Logger log = LoggerFactory.getLogger(ReportPdfResource.class);

  /** 리소스 경로별 data URI 다. 빈 문자열은 "읽어 봤지만 없었다"를 뜻한다. */
  private static final Map<String, String> CACHE = new ConcurrentHashMap<>();

  private ReportPdfResource() {}

  /**
   * PNG 리소스를 {@code <img src>} 에 넣을 data URI 로 읽는다.
   *
   * @param resource classpath 절대 경로
   * @return data URI, 못 읽었으면 {@link Optional#empty()}
   */
  static Optional<String> pngDataUri(String resource) {
    String cached = CACHE.computeIfAbsent(resource, ReportPdfResource::load);
    return cached.isEmpty() ? Optional.empty() : Optional.of(cached);
  }

  private static String load(String resource) {
    try (InputStream stream = ReportPdfResource.class.getResourceAsStream(resource)) {
      if (stream == null) {
        log.warn("리포트 PDF 리소스를 찾을 수 없습니다. resource={}", resource);
        return "";
      }
      return "data:image/png;base64," + Base64.getEncoder().encodeToString(stream.readAllBytes());
    } catch (IOException exception) {
      log.warn("리포트 PDF 리소스를 읽지 못했습니다. resource={}", resource, exception);
      return "";
    }
  }
}
