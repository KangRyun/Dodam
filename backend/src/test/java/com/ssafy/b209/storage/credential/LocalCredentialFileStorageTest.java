package com.ssafy.b209.storage.credential;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.nio.file.Files;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LocalCredentialFileStorageTest {

  @TempDir java.nio.file.Path tempDir;

  @Test
  void storesSignatureVerifiedPdfAndDeletesIt() {
    LocalCredentialFileStorage storage = storage(10_485_760L);
    byte[] content = "%PDF-1.7\ncredential".getBytes();

    StoredCredentialFile stored =
        storage.store(new StoreCredentialFileCommand(content, "application/pdf", "license.pdf"));

    assertThat(stored.contentType()).isEqualTo("application/pdf");
    assertThat(stored.size()).isEqualTo(content.length);
    assertThat(stored.storageKey()).startsWith("2026/08/03/").endsWith(".pdf");
    assertThat(stored.storageKeyHash()).hasSize(64);
    assertThat(tempDir.resolve(stored.storageKey())).exists();

    storage.delete(stored.storageKey());
    assertThat(Files.exists(tempDir.resolve(stored.storageKey()))).isFalse();
  }

  @Test
  void rejectsDeclaredTypeOrExtensionDifferentFromSignature() {
    LocalCredentialFileStorage storage = storage(10_485_760L);

    assertThatThrownBy(
            () ->
                storage.store(
                    new StoreCredentialFileCommand(
                        "%PDF-1.7\n".getBytes(), "image/png", "license.png")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.CREDENTIAL_FILE_INVALID));
  }

  @Test
  void checksActualBytesAgainstConfiguredLimit() {
    LocalCredentialFileStorage storage = storage(8L);

    assertThatThrownBy(
            () ->
                storage.store(
                    new StoreCredentialFileCommand(
                        "%PDF-1.7\n".getBytes(), "application/pdf", "license.pdf")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.CREDENTIAL_FILE_TOO_LARGE));
  }

  private LocalCredentialFileStorage storage(long maxSize) {
    return new LocalCredentialFileStorage(
        new CredentialFileStorageProperties(tempDir, maxSize),
        Clock.fixed(Instant.parse("2026-08-03T00:00:00Z"), ZoneOffset.UTC));
  }
}
