package com.ssafy.b209.storage.s3;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.audio.AudioStorageErrorCode;
import com.ssafy.b209.storage.audio.AudioStorageProperties;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import com.ssafy.b209.storage.audio.StoredAudioContent;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.URI;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
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
class S3AudioStorageTest {

  private static final byte[] WAV = wav(1);

  @Mock private S3Client s3Client;
  @TempDir Path tempDir;

  private S3AudioStorage storage;

  @BeforeEach
  void setUp() {
    LocalAudioStorage staging =
        new LocalAudioStorage(
            new AudioStorageProperties(tempDir.resolve("audio"), 20 * 1024 * 1024),
            Clock.fixed(Instant.parse("2026-07-25T00:00:00Z"), ZoneOffset.UTC));
    storage = new S3AudioStorage(s3Client, properties(), staging);
  }

  @Test
  void promotesValidatedAudioUnderConfiguredPrefixAndRemovesLocalFile() throws IOException {
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenReturn(PutObjectResponse.builder().build());

    StoredAudio stored =
        storage.promote(
            storage.stage(
                new StoreAudioCommand(
                    new ByteArrayInputStream(WAV), WAV.length, "audio/wav", "answer.wav")));

    ArgumentCaptor<PutObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(PutObjectRequest.class);
    ArgumentCaptor<RequestBody> bodyCaptor = ArgumentCaptor.forClass(RequestBody.class);
    verify(s3Client).putObject(requestCaptor.capture(), bodyCaptor.capture());
    assertThat(requestCaptor.getValue().bucket()).isEqualTo("dodam");
    assertThat(requestCaptor.getValue().key()).isEqualTo("audio/" + stored.storageKey());
    assertThat(requestCaptor.getValue().contentType()).isEqualTo("audio/wav");
    assertThat(bodyCaptor.getValue().contentLength()).isEqualTo(WAV.length);
    try (var paths = Files.walk(tempDir.resolve("audio"))) {
      assertThat(paths.filter(Files::isRegularFile)).isEmpty();
    }
  }

  @Test
  void promotesTtsAudioUnderDedicatedCachePrefix() {
    LocalAudioStorage staging =
        new LocalAudioStorage(
            new AudioStorageProperties(tempDir.resolve("tts"), 20 * 1024 * 1024),
            Clock.fixed(Instant.parse("2026-07-25T00:00:00Z"), ZoneOffset.UTC));
    S3AudioStorage ttsStorage =
        new S3AudioStorage(s3Client, properties(), properties().ttsPrefix(), staging);
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenReturn(PutObjectResponse.builder().build());

    StoredAudio stored =
        ttsStorage.promote(
            ttsStorage.stage(
                new StoreAudioCommand(
                    new ByteArrayInputStream(WAV), WAV.length, "audio/wav", "tts.wav")));

    ArgumentCaptor<PutObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(PutObjectRequest.class);
    verify(s3Client).putObject(requestCaptor.capture(), any(RequestBody.class));
    assertThat(requestCaptor.getValue().key()).isEqualTo("tts-cache/" + stored.storageKey());
  }

  @Test
  void readsS3AudioAsAClosableStream() throws Exception {
    when(s3Client.getObject(any(GetObjectRequest.class)))
        .thenReturn(
            new ResponseInputStream<>(
                GetObjectResponse.builder()
                    .contentType("audio/wav")
                    .contentLength((long) WAV.length)
                    .build(),
                AbortableInputStream.create(new ByteArrayInputStream(WAV))));

    try (StoredAudioContent content = storage.read("2026/07/25/answer.wav")) {
      assertThat(content.contentType()).isEqualTo("audio/wav");
      assertThat(content.size()).isEqualTo(WAV.length);
      assertThat(content.inputStream().readAllBytes()).isEqualTo(WAV);
    }

    ArgumentCaptor<GetObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(GetObjectRequest.class);
    verify(s3Client).getObject(requestCaptor.capture());
    assertThat(requestCaptor.getValue().key()).isEqualTo("audio/2026/07/25/answer.wav");
  }

  @Test
  void rejectsTraversalBeforeCallingS3() {
    assertBusinessError(
        () -> storage.read("../secret.wav"), AudioStorageErrorCode.INVALID_STORAGE_PATH);

    verify(s3Client, never()).getObject(any(GetObjectRequest.class));
  }

  @Test
  void deletesOnlyTheConfiguredAudioPrefixObject() {
    storage.delete("2026/07/25/answer.wav");

    ArgumentCaptor<DeleteObjectRequest> requestCaptor =
        ArgumentCaptor.forClass(DeleteObjectRequest.class);
    verify(s3Client).deleteObject(requestCaptor.capture());
    assertThat(requestCaptor.getValue().bucket()).isEqualTo("dodam");
    assertThat(requestCaptor.getValue().key()).isEqualTo("audio/2026/07/25/answer.wav");
  }

  @Test
  void mapsS3UploadFailureAndRemovesLocalStagingFile() throws IOException {
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenThrow(S3Exception.builder().message("simulated failure").build());

    assertBusinessError(
        () ->
            storage.promote(
                storage.stage(
                    new StoreAudioCommand(
                        new ByteArrayInputStream(WAV), WAV.length, "audio/wav", "answer.wav"))),
        AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
    try (var paths = Files.walk(tempDir.resolve("audio"))) {
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

  private void assertBusinessError(Runnable action, AudioStorageErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
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
