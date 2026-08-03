package com.ssafy.b209.storage.s3;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.storage.credential.CredentialFileStorageProperties;
import com.ssafy.b209.storage.credential.StoreCredentialFileCommand;
import java.net.URI;
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
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;

@ExtendWith(MockitoExtension.class)
class S3CredentialFileStorageTest {

  @Mock private S3Client s3Client;
  @TempDir Path tempDir;
  private S3CredentialFileStorage storage;

  @BeforeEach
  void setUp() {
    S3StorageProperties s3Properties =
        new S3StorageProperties(
            URI.create("http://localhost:9000"),
            "ap-northeast-2",
            "dodam",
            "access",
            "secret",
            "images",
            "audio",
            "tts-cache",
            "credentials",
            true);
    storage =
        new S3CredentialFileStorage(
            s3Client,
            s3Properties,
            new CredentialFileStorageProperties(tempDir, 10_485_760L),
            Clock.fixed(Instant.parse("2026-08-03T00:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  void uploadsUnderCredentialPrefixAndRemovesStagingFile() throws Exception {
    when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
        .thenReturn(PutObjectResponse.builder().build());

    var stored =
        storage.store(
            new StoreCredentialFileCommand(
                "%PDF-1.7\n".getBytes(), "application/pdf", "license.pdf"));

    ArgumentCaptor<PutObjectRequest> captor = ArgumentCaptor.forClass(PutObjectRequest.class);
    verify(s3Client).putObject(captor.capture(), any(RequestBody.class));
    assertThat(captor.getValue().key()).isEqualTo("credentials/" + stored.storageKey());
    try (var paths = Files.walk(tempDir)) {
      assertThat(paths.filter(Files::isRegularFile)).isEmpty();
    }
  }

  @Test
  void deletesOnlyCredentialPrefixObject() {
    storage.delete("2026/08/03/file.pdf");

    ArgumentCaptor<DeleteObjectRequest> captor = ArgumentCaptor.forClass(DeleteObjectRequest.class);
    verify(s3Client).deleteObject(captor.capture());
    assertThat(captor.getValue().key()).isEqualTo("credentials/2026/08/03/file.pdf");
  }
}
