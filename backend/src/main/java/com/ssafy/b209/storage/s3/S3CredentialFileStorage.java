package com.ssafy.b209.storage.s3;

import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import com.ssafy.b209.storage.credential.CredentialFileStorageProperties;
import com.ssafy.b209.storage.credential.LocalCredentialFileStorage;
import com.ssafy.b209.storage.credential.StoreCredentialFileCommand;
import com.ssafy.b209.storage.credential.StoredCredentialFile;
import java.time.Clock;
import java.util.Objects;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/** 로컬 검증 결과를 MinIO의 자격 증빙 Prefix로 승격하는 Storage 구현체다. */
public final class S3CredentialFileStorage implements CredentialFileStorage {
  private final S3Client s3Client;
  private final String bucket;
  private final String prefix;
  private final LocalCredentialFileStorage stagingStorage;

  /**
   * S3 호환 자격 증빙 Storage를 생성한다.
   *
   * @param s3Client S3 호환 API Client
   * @param s3Properties Bucket과 자격 증빙 Prefix 설정
   * @param fileProperties staging Root와 최대 파일 크기
   * @param clock 날짜 기반 상대 Key 생성 시계
   */
  public S3CredentialFileStorage(
      S3Client s3Client,
      S3StorageProperties s3Properties,
      CredentialFileStorageProperties fileProperties,
      Clock clock) {
    this.s3Client = Objects.requireNonNull(s3Client);
    this.bucket = Objects.requireNonNull(s3Properties).bucket();
    this.prefix = s3Properties.credentialPrefix();
    this.stagingStorage = new LocalCredentialFileStorage(fileProperties, clock);
  }

  /** {@inheritDoc} */
  @Override
  public StoredCredentialFile store(StoreCredentialFileCommand command) {
    StoredCredentialFile staged = stagingStorage.store(command);
    try {
      s3Client.putObject(
          PutObjectRequest.builder()
              .bucket(bucket)
              .key(objectKey(staged.storageKey()))
              .contentType(staged.contentType())
              .contentLength(staged.size())
              .build(),
          RequestBody.fromBytes(command.content()));
      return staged;
    } catch (SdkException exception) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED, exception);
    } finally {
      try {
        stagingStorage.delete(staged.storageKey());
      } catch (RuntimeException ignored) {
        // 임시 파일 정리 실패가 실제 S3 저장 결과를 가리지 않도록 한다.
      }
    }
  }

  /** {@inheritDoc} */
  @Override
  public void delete(String storageKey) {
    if (!isSafeKey(storageKey)) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED);
    }
    try {
      s3Client.deleteObject(
          DeleteObjectRequest.builder().bucket(bucket).key(objectKey(storageKey)).build());
    } catch (SdkException exception) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED, exception);
    }
  }

  private String objectKey(String storageKey) {
    return prefix + "/" + storageKey;
  }

  private boolean isSafeKey(String key) {
    return key != null
        && !key.isBlank()
        && !key.startsWith("/")
        && !key.contains("\\")
        && !key.contains("..");
  }
}
