package com.ssafy.b209.infrastructure.ai.image;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.StoredImageContent;
import io.swagger.v3.oas.annotations.Hidden;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * AI 컨테이너가 분석 대상 이미지를 일회성 Token으로 조회하는 내부 HTTP API다.
 *
 * <p>공개 API나 Swagger에 노출하지 않으며, 응답 캐시와 저장 경로 노출을 금지한다. 네트워크 접근 제한은 Docker 내부망과 Nginx 경로 정책이 담당하고,
 * Token은 최초 요청에서 원자적으로 소비된다.
 */
@Hidden
@RestController
@RequestMapping("/internal/v1/ai-images")
@ConditionalOnProperty(prefix = "app.ai.drawing-analysis", name = "mode", havingValue = "http")
public class AiImageAccessController {

  private static final int STREAM_BUFFER_SIZE = 8192;

  private final AiImageAccessService service;

  /**
   * 내부 이미지 조회 Controller를 구성한다.
   *
   * @param service Token 소비와 Storage 조회를 담당하는 Service
   */
  public AiImageAccessController(AiImageAccessService service) {
    this.service = service;
  }

  /**
   * 유효한 Token에 연결된 이미지를 캐시 없이 스트리밍한다.
   *
   * @param token URL 경로로 전달된 일회성 Token
   * @return 원본 이미지 Content-Type과 크기를 포함한 Stream 응답
   * @throws BusinessException Token 또는 이미지가 유효하지 않거나 Infrastructure가 불가용한 경우
   */
  @GetMapping("/{token}")
  public ResponseEntity<StreamingResponseBody> getImage(@PathVariable String token) {
    StoredImageContent content = service.consume(token);
    StreamingResponseBody body =
        outputStream -> {
          try (StoredImageContent opened = content) {
            byte[] buffer = new byte[STREAM_BUFFER_SIZE];
            int read;
            while ((read = opened.inputStream().read(buffer)) != -1) {
              outputStream.write(buffer, 0, read);
            }
          }
        };
    return ResponseEntity.ok()
        .cacheControl(CacheControl.noStore())
        .contentType(MediaType.parseMediaType(content.contentType()))
        .contentLength(content.size())
        .body(body);
  }
}
