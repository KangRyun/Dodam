package com.ssafy.b209.infrastructure.ai.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import java.net.URI;
import java.time.Duration;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataAccessResourceFailureException;

@ExtendWith(MockitoExtension.class)
class AiImageAccessServiceTest {

  private static final String TOKEN = "abcdefghijklmnopqrstuvwxyzABCDEFGH012345678";

  @Mock private AiImageAccessTokenStore tokenStore;
  @Mock private ImageStorage imageStorage;

  private AiImageAccessService service;

  @BeforeEach
  void setUp() {
    service =
        new AiImageAccessService(
            tokenStore,
            imageStorage,
            new AiImageAccessProperties(URI.create("http://backend:8080"), Duration.ofSeconds(60)));
  }

  @Test
  void createsAnInternalOneTimeReadUrl() {
    when(tokenStore.issue("image.png", Duration.ofSeconds(60))).thenReturn(TOKEN);

    URI url = service.createReadUrl("image.png");

    assertThat(url).isEqualTo(URI.create("http://backend:8080/internal/v1/ai-images/" + TOKEN));
  }

  @Test
  void mapsIssuingStoreFailureToClientRequestFailure() {
    when(tokenStore.issue("image.png", Duration.ofSeconds(60)))
        .thenThrow(new DataAccessResourceFailureException("redis unavailable"));

    assertThatThrownBy(() -> service.createReadUrl("image.png"))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(DrawingAnalysisClientException.Type.REQUEST_FAILED));
  }

  @Test
  void hidesExpiredReusedAndMissingStorageKeysBehindTheSameNotFoundError() {
    when(tokenStore.consume(TOKEN)).thenReturn(Optional.empty());

    assertBusinessError(
        () -> service.consume(TOKEN), AiImageAccessErrorCode.IMAGE_ACCESS_NOT_FOUND);

    when(tokenStore.consume(TOKEN)).thenReturn(Optional.of("missing.png"));
    when(imageStorage.read("missing.png"))
        .thenThrow(new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND));

    assertBusinessError(
        () -> service.consume(TOKEN), AiImageAccessErrorCode.IMAGE_ACCESS_NOT_FOUND);
  }

  @Test
  void mapsRedisFailureDuringConsumptionToServiceUnavailable() {
    when(tokenStore.consume(TOKEN))
        .thenThrow(new DataAccessResourceFailureException("redis unavailable"));

    assertBusinessError(
        () -> service.consume(TOKEN), AiImageAccessErrorCode.IMAGE_ACCESS_UNAVAILABLE);
  }

  private void assertBusinessError(Runnable action, AiImageAccessErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
