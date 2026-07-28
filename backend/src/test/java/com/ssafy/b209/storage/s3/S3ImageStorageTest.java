package com.ssafy.b209.storage.s3;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import com.ssafy.b209.storage.image.ImageStorageProperties;
import com.ssafy.b209.storage.image.LocalImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.s3.model.S3Exception;

@ExtendWith(MockitoExtension.class)
class S3ImageStorageTest {

  private static final byte[] PNG = imageBytes();

  @Mock private S3Client s3Client;
  @TempDir Path tempDir;

  private S3ImageStorage storage;

  @BeforeEach
  void setUp() {
    LocalImageStorage staging =
        new LocalImageStorage(
            new ImageStorageProperties(tempDir.resolve("images"), 1024 * 1024),
            Clock.fixed(Instant.parse("2026-07-25T00:00:00Z"), ZoneOffset.UTC));
    storage = new S3ImageStorage(s3Client, properties(), staging);
  }

  @Test
  void storesValidatedImageUnderConfiguredPrefixAndRemovesLocalStagingFile() throws IOException {
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenReturn(PutObjectResponse.builder().build());

    StoredImage stored =
        storage.store(
            new StoreImageCommand(
                new ByteArrayInputStream(PNG), PNG.length, "image/png", "drawing.png"));

    ArgumentCaptor<PutObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(PutObjectRequest.class);
    ArgumentCaptor<RequestBody> bodyCaptor = ArgumentCaptor.forClass(RequestBody.class);
    verify(s3Client).putObject(requestCaptor.capture(), bodyCaptor.capture());
    assertThat(requestCaptor.getValue().bucket()).isEqualTo("dodam");
    assertThat(requestCaptor.getValue().key()).isEqualTo("images/" + stored.storageKey());
    assertThat(requestCaptor.getValue().contentType()).isEqualTo("image/png");
    assertThat(bodyCaptor.getValue().contentLength()).isEqualTo(PNG.length);
    try (var paths = Files.walk(tempDir.resolve("images"))) {
      assertThat(paths.filter(Files::isRegularFile)).isEmpty();
    }
  }

  @Test
  void readsS3ImageAsAClosableStream() throws Exception {
    when(s3Client.getObject(any(GetObjectRequest.class)))
        .thenReturn(
            new ResponseInputStream<>(
                GetObjectResponse.builder()
                    .contentType("image/png")
                    .contentLength((long) PNG.length)
                    .build(),
                AbortableInputStream.create(new ByteArrayInputStream(PNG))));

    try (StoredImageContent content = storage.read("2026/07/25/image.png")) {
      assertThat(content.contentType()).isEqualTo("image/png");
      assertThat(content.size()).isEqualTo(PNG.length);
      assertThat(content.inputStream().readAllBytes()).isEqualTo(PNG);
    }

    ArgumentCaptor<GetObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(GetObjectRequest.class);
    verify(s3Client).getObject(requestCaptor.capture());
    assertThat(requestCaptor.getValue().key()).isEqualTo("images/2026/07/25/image.png");
  }

  @Test
  void rejectsTraversalBeforeCallingS3() {
    assertBusinessError(
        () -> storage.read("../secret.png"), ImageStorageErrorCode.INVALID_STORAGE_PATH);

    verify(s3Client, never()).getObject(any(GetObjectRequest.class));
  }

  @Test
  void deletesOnlyTheConfiguredImagePrefixObject() {
    storage.delete("2026/07/25/image.png");

    ArgumentCaptor<DeleteObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(DeleteObjectRequest.class);
    verify(s3Client).deleteObject(requestCaptor.capture());
    assertThat(requestCaptor.getValue().bucket()).isEqualTo("dodam");
    assertThat(requestCaptor.getValue().key()).isEqualTo("images/2026/07/25/image.png");
  }

  @Test
  void mapsS3UploadFailureAndRemovesLocalStagingFile() throws IOException {
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenThrow(S3Exception.builder().message("simulated failure").build());

    assertBusinessError(
        () ->
            storage.store(
                new StoreImageCommand(
                    new ByteArrayInputStream(PNG), PNG.length, "image/png", "drawing.png")),
        ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
    try (var paths = Files.walk(tempDir.resolve("images"))) {
      assertThat(paths.filter(Files::isRegularFile)).isEmpty();
    }
  }

  private S3StorageProperties properties() {
    return new S3StorageProperties(
        URI.create("http://localhost:9000"),
        "ap-northeast-2",
        "dodam",
        "access",
        "secret",
        "images",
        "audio",
        "tts-cache",
        true);
  }

  private void assertBusinessError(Runnable action, ImageStorageErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }

  private static byte[] imageBytes() {
    BufferedImage image = new BufferedImage(320, 320, BufferedImage.TYPE_INT_RGB);
    try (ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      if (!ImageIO.write(image, "png", output)) {
        throw new IllegalStateException("PNG writer is unavailable");
      }
      return output.toByteArray();
    } catch (IOException exception) {
      throw new IllegalStateException("Failed to create test PNG", exception);
    }
  }
}
