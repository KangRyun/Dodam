package com.ssafy.b209.storage.s3;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageProperties;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import com.ssafy.b209.storage.audio.StoredAudioContent;
import com.ssafy.b209.storage.image.ImageStorage;
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
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

@Testcontainers(disabledWithoutDocker = true)
class S3StorageIntegrationTest {

  private static final String ACCESS_KEY = "integration-user";
  private static final String SECRET_KEY = "integration-password";
  private static final String BUCKET = "dodam";
  private static final byte[] PNG = imageBytes();
  private static final byte[] WAV = wav(1);
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-25T00:00:00Z"), ZoneOffset.UTC);

  @Container
  static final GenericContainer<?> MINIO =
      new GenericContainer<>(DockerImageName.parse("minio/minio:RELEASE.2025-04-22T22-12-26Z"))
          .withExposedPorts(9000)
          .withEnv("MINIO_ROOT_USER", ACCESS_KEY)
          .withEnv("MINIO_ROOT_PASSWORD", SECRET_KEY)
          .withCommand("server", "/data", "--address", ":9000")
          .waitingFor(Wait.forHttp("/minio/health/live").forPort(9000));

  @TempDir Path tempDir;

  private static S3Client s3Client;
  private static S3StorageProperties properties;

  @BeforeAll
  static void prepareBucket() {
    URI endpoint = URI.create("http://" + MINIO.getHost() + ":" + MINIO.getMappedPort(9000));
    properties =
        new S3StorageProperties(
            endpoint, "ap-northeast-2", BUCKET, ACCESS_KEY, SECRET_KEY, "images", "audio", true);
    s3Client =
        S3Client.builder()
            .endpointOverride(endpoint)
            .region(Region.of(properties.region()))
            .credentialsProvider(
                StaticCredentialsProvider.create(
                    AwsBasicCredentials.create(ACCESS_KEY, SECRET_KEY)))
            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
            .httpClientBuilder(UrlConnectionHttpClient.builder())
            .build();
    s3Client.createBucket(request -> request.bucket(BUCKET));
  }

  @AfterAll
  static void closeClient() {
    if (s3Client != null) {
      s3Client.close();
    }
  }

  @Test
  void storesReadsAndDeletesImageAndAudioAgainstMinio() throws Exception {
    ImageStorage imageStorage =
        new S3ImageStorage(
            s3Client,
            properties,
            new LocalImageStorage(
                new ImageStorageProperties(tempDir.resolve("images"), 1024 * 1024), CLOCK));
    AudioStorage audioStorage =
        new S3AudioStorage(
            s3Client,
            properties,
            new LocalAudioStorage(
                new AudioStorageProperties(tempDir.resolve("audio"), 20 * 1024 * 1024), CLOCK));

    StoredImage image =
        imageStorage.store(
            new StoreImageCommand(
                new ByteArrayInputStream(PNG), PNG.length, "image/png", "drawing.png"));
    try (StoredImageContent content = imageStorage.read(image.storageKey())) {
      assertThat(content.inputStream().readAllBytes()).isEqualTo(PNG);
    }

    StoredAudio audio =
        audioStorage.promote(
            audioStorage.stage(
                new StoreAudioCommand(
                    new ByteArrayInputStream(WAV), WAV.length, "audio/wav", "answer.wav")));
    try (StoredAudioContent content = audioStorage.read(audio.storageKey())) {
      assertThat(content.inputStream().readAllBytes()).isEqualTo(WAV);
    }

    imageStorage.delete(image.storageKey());
    audioStorage.delete(audio.storageKey());

    assertThat(s3Client.listObjectsV2(request -> request.bucket(BUCKET)).contents()).isEmpty();
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

  private static byte[] wav(int seconds) {
    int sampleRate = 8000;
    int dataLength = sampleRate * seconds;
    ByteBuffer buffer = ByteBuffer.allocate(44 + dataLength).order(ByteOrder.LITTLE_ENDIAN);
    buffer.put("RIFF".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(36 + dataLength);
    buffer.put("WAVEfmt ".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(16);
    buffer.putShort((short) 1);
    buffer.putShort((short) 1);
    buffer.putInt(sampleRate);
    buffer.putInt(sampleRate);
    buffer.putShort((short) 1);
    buffer.putShort((short) 8);
    buffer.put("data".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(dataLength);
    return buffer.array();
  }
}
