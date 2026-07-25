package com.ssafy.b209.drawing.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.drawing.dto.response.DrawingAssetFileResource;
import com.ssafy.b209.drawing.service.DrawingAssetFileQueryService;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@ExtendWith(MockitoExtension.class)
class DrawingAssetFileControllerTest {

  @Mock private DrawingAssetFileQueryService service;

  @Test
  void streamsTheImageWithPrivateNoStoreCachingAndClosesTheResource() throws Exception {
    byte[] bytes = {1, 2, 3, 4};
    AtomicBoolean closed = new AtomicBoolean();
    ByteArrayInputStream inputStream =
        new ByteArrayInputStream(bytes) {
          @Override
          public void close() throws IOException {
            closed.set(true);
            super.close();
          }
        };
    given(service.getFile(20L))
        .willReturn(
            new DrawingAssetFileResource(
                new StoredImageContent(inputStream, "image/png", bytes.length)));
    DrawingAssetFileController controller = new DrawingAssetFileController(service);

    ResponseEntity<StreamingResponseBody> response = controller.getFile(20L);
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    response.getBody().writeTo(output);

    assertThat(response.getStatusCode().value()).isEqualTo(200);
    assertThat(response.getHeaders().getContentType().toString()).isEqualTo("image/png");
    assertThat(response.getHeaders().getContentLength()).isEqualTo(bytes.length);
    assertThat(response.getHeaders().getCacheControl()).contains("private").contains("no-store");
    assertThat(response.getHeaders().containsKey("Content-Disposition")).isFalse();
    assertThat(output.toByteArray()).isEqualTo(bytes);
    assertThat(closed).isTrue();
  }
}
