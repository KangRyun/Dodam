package com.ssafy.b209.infrastructure.ai.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@ExtendWith(MockitoExtension.class)
class AiImageAccessControllerTest {

  private static final String TOKEN = "abcdefghijklmnopqrstuvwxyzABCDEFGH012345678";

  @Mock private AiImageAccessService service;

  @Test
  void streamsTheImageWithoutCachingOrDisclosingStorageMetadata() throws Exception {
    byte[] bytes = {1, 2, 3, 4};
    when(service.consume(TOKEN))
        .thenReturn(
            new StoredImageContent(new ByteArrayInputStream(bytes), "image/png", bytes.length));
    AiImageAccessController controller = new AiImageAccessController(service);

    ResponseEntity<StreamingResponseBody> response = controller.getImage(TOKEN);
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    response.getBody().writeTo(output);

    assertThat(response.getStatusCode().value()).isEqualTo(200);
    assertThat(response.getHeaders().getContentType().toString()).isEqualTo("image/png");
    assertThat(response.getHeaders().getContentLength()).isEqualTo(bytes.length);
    assertThat(response.getHeaders().getCacheControl()).contains("no-store");
    assertThat(response.getHeaders().containsKey("Content-Disposition")).isFalse();
    assertThat(output.toByteArray()).isEqualTo(bytes);
  }
}
