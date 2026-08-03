package com.ssafy.b209.storage.credential;

import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Objects;
import java.util.UUID;

/** 자격 증빙을 Signature 검증한 뒤 전용 로컬 Root에 저장하는 구현체다. */
public final class LocalCredentialFileStorage implements CredentialFileStorage {
  private final Path root;
  private final long maxSize;
  private final Clock clock;

  /**
   * 로컬 자격 증빙 Storage를 생성한다.
   *
   * @param properties 전용 Root와 최대 파일 크기
   * @param clock 날짜 기반 상대 Key 생성 시계
   */
  public LocalCredentialFileStorage(CredentialFileStorageProperties properties, Clock clock) {
    this.root = Objects.requireNonNull(properties).root();
    this.maxSize = properties.maxSize();
    this.clock = Objects.requireNonNull(clock);
  }

  /** {@inheritDoc} */
  @Override
  public StoredCredentialFile store(StoreCredentialFileCommand command) {
    CredentialFileFormat format = CredentialFileFormat.validate(command, maxSize);
    LocalDate date = LocalDate.now(clock);
    String filename = UUID.randomUUID() + "." + format.extension();
    String key =
        String.format(
            Locale.ROOT,
            "%04d/%02d/%02d/%s",
            date.getYear(),
            date.getMonthValue(),
            date.getDayOfMonth(),
            filename);
    Path target = root.resolve(key).normalize();
    if (!target.startsWith(root)) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED);
    }
    try {
      Files.createDirectories(target.getParent());
      Files.write(
          target, command.content(), StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
      return stored(key, format, command.content());
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED, exception);
    }
  }

  /** {@inheritDoc} */
  @Override
  public void delete(String storageKey) {
    Path target = safeTarget(storageKey);
    try {
      Files.deleteIfExists(target);
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED, exception);
    }
  }

  static StoredCredentialFile stored(
      String storageKey, CredentialFileFormat format, byte[] content) {
    return new StoredCredentialFile(
        storageKey,
        sha256(storageKey.getBytes(java.nio.charset.StandardCharsets.UTF_8)),
        format.contentType(),
        content.length);
  }

  private Path safeTarget(String key) {
    if (key == null || key.isBlank() || key.contains("\\") || key.startsWith("/")) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED);
    }
    Path target = root.resolve(key).normalize();
    if (!target.startsWith(root) || key.contains("..")) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED);
    }
    return target;
  }

  private static String sha256(byte[] value) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is unavailable", exception);
    }
  }
}
