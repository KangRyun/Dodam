package com.ssafy.b209.infrastructure.ai.image;

import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisImageUrlProvider;
import java.net.URI;
import java.util.Objects;

/** Redis 일회성 Token Service를 그림 분석 이미지 URL 경계에 연결한다. */
public final class RedisDrawingAnalysisImageUrlProvider implements DrawingAnalysisImageUrlProvider {

  private final AiImageAccessService service;

  /**
   * Provider를 구성한다.
   *
   * @param service 일회성 이미지 URL 발급 Service
   */
  public RedisDrawingAnalysisImageUrlProvider(AiImageAccessService service) {
    this.service = Objects.requireNonNull(service, "service must not be null");
  }

  @Override
  public URI createReadUrl(String storageKey) {
    return service.createReadUrl(storageKey);
  }
}
