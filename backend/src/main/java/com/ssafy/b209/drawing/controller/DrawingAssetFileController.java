package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.response.DrawingAssetFileResource;
import com.ssafy.b209.drawing.service.DrawingAssetFileQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 인증된 보호자가 그림 활동에서 저장한 이미지 파일을 조회하는 HTTP API다.
 *
 * <p>Storage Key나 서버 경로를 노출하지 않고 요청마다 그림 세션 소유권을 검증한 뒤 파일을 스트리밍한다. 민감한 아동 그림이 브라우저나 공유 Cache에 남지
 * 않도록 모든 성공 응답에 {@code Cache-Control: private, no-store}를 적용한다.
 */
@Tag(name = "Drawing Assets", description = "그림 파일 조회 API")
@RestController
@RequestMapping("/api/v1/drawing-assets")
public class DrawingAssetFileController {

  private static final int STREAM_BUFFER_SIZE = 8192;

  private final DrawingAssetFileQueryService drawingAssetFileQueryService;

  /**
   * 그림 파일 조회 Controller를 구성한다.
   *
   * @param drawingAssetFileQueryService 인증·소유권 검증 후 파일을 여는 Service
   */
  public DrawingAssetFileController(DrawingAssetFileQueryService drawingAssetFileQueryService) {
    this.drawingAssetFileQueryService = drawingAssetFileQueryService;
  }

  /**
   * 현재 보호자가 접근할 수 있는 그림 파일을 원본 MIME Type으로 스트리밍한다.
   *
   * @param drawingAssetId 조회할 그림 파일 식별자
   * @return 파일 크기와 Cache 금지 Header를 포함한 이미지 Stream 응답
   * @throws BusinessException 인증 정보가 없거나 접근 가능한 그림 파일을 찾을 수 없는 경우
   */
  @Operation(summary = "그림 파일 조회", description = "JWT 인증과 그림 세션 소유권을 확인한 뒤 저장된 그림을 프록시 스트리밍합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "그림 파일 스트리밍 성공",
        content = @Content(mediaType = MediaType.APPLICATION_OCTET_STREAM_VALUE)),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "그림 파일이 없거나 접근할 수 없는 그림 활동",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{drawingAssetId}/file")
  public ResponseEntity<StreamingResponseBody> getFile(@PathVariable Long drawingAssetId) {
    DrawingAssetFileResource resource = drawingAssetFileQueryService.getFile(drawingAssetId);
    StreamingResponseBody body =
        outputStream -> {
          try (DrawingAssetFileResource opened = resource) {
            byte[] buffer = new byte[STREAM_BUFFER_SIZE];
            int read;
            while ((read = opened.content().inputStream().read(buffer)) != -1) {
              outputStream.write(buffer, 0, read);
            }
          }
        };
    return ResponseEntity.ok()
        .cacheControl(CacheControl.noStore().cachePrivate())
        .contentType(MediaType.parseMediaType(resource.content().contentType()))
        .contentLength(resource.content().size())
        .body(body);
  }
}
