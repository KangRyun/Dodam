package com.ssafy.b209.child.controller;

import com.ssafy.b209.child.dto.response.ChildProfileImageFileResource;
import com.ssafy.b209.child.service.ChildProfileImageFileQueryService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * JWT 인증과 아동 접근 권한을 확인한 뒤 프로필 이미지 원본을 중계한다.
 *
 * <p>Storage Key는 노출하지 않으며 민감한 아동 이미지가 공유 Cache에 남지 않도록 {@code private, no-store}를 적용한다.
 */
@RestController
@RequestMapping("/api/v1/child-profile-images")
public class ChildProfileImageFileController {

  private static final int STREAM_BUFFER_SIZE = 8192;
  private final ChildProfileImageFileQueryService service;

  public ChildProfileImageFileController(ChildProfileImageFileQueryService service) {
    this.service = service;
  }

  /**
   * 연결된 아동 프로필 이미지를 원본 MIME Type으로 전송한다.
   *
   * @param profileImageFileId 프로필 이미지 파일 ID
   * @return 이미지 Stream 응답
   */
  @GetMapping("/{profileImageFileId}/file")
  public ResponseEntity<StreamingResponseBody> getFile(@PathVariable String profileImageFileId) {
    ChildProfileImageFileResource resource = service.getFile(profileImageFileId);
    StreamingResponseBody body =
        outputStream -> {
          try (ChildProfileImageFileResource opened = resource) {
            opened.content().inputStream().transferTo(outputStream);
          }
        };
    return ResponseEntity.ok()
        .cacheControl(CacheControl.noStore().cachePrivate())
        .contentType(MediaType.parseMediaType(resource.content().contentType()))
        .contentLength(resource.content().size())
        .body(body);
  }
}
