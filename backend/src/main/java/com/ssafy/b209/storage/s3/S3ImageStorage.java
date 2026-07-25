package com.ssafy.b209.storage.s3;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import com.ssafy.b209.storage.image.LocalImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.util.Objects;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

/**
 * 기존 이미지 검증 규칙을 통과한 파일을 S3 호환 Object Storage에 저장한다.
 *
 * <p>{@link LocalImageStorage}는 업로드 전 Signature·크기·Checksum 검증과 임시 staging에만 사용한다. S3 객체는 {@code
 * images/} Prefix 아래에 저장하며 DB에는 Prefix를 제외한 기존 Storage Key 형식을 유지한다.
 */
public final class S3ImageStorage implements ImageStorage {

  private final S3Client s3Client;
  private final String bucket;
  private final String prefix;
  private final LocalImageStorage stagingStorage;

  /**
   * S3 이미지 저장소를 생성한다.
   *
   * @param s3Client S3 호환 API Client
   * @param properties Bucket과 이미지 Prefix 설정
   * @param stagingStorage 기존 이미지 검증을 수행할 Local staging 저장소
   */
  public S3ImageStorage(
      S3Client s3Client, S3StorageProperties properties, LocalImageStorage stagingStorage) {
    this.s3Client = Objects.requireNonNull(s3Client, "s3Client must not be null");
    S3StorageProperties requiredProperties =
        Objects.requireNonNull(properties, "properties must not be null");
    this.bucket = requiredProperties.bucket();
    this.prefix = requiredProperties.imagePrefix();
    this.stagingStorage = Objects.requireNonNull(stagingStorage, "stagingStorage must not be null");
  }

  /**
   * 이미지를 검증한 뒤 S3에 업로드하고 Local staging 파일을 정리한다.
   *
   * @param command 이미지 Stream과 검증 Metadata
   * @return DB에 저장할 Prefix 제외 Storage Key와 이미지 Metadata
   * @throws BusinessException 이미지가 유효하지 않거나 S3에 안전하게 저장할 수 없는 경우
   */
  @Override
  public StoredImage store(StoreImageCommand command) {
    StoredImage staged = stagingStorage.store(command);
    try (StoredImageContent content = stagingStorage.read(staged.storageKey())) {
      PutObjectRequest request =
          PutObjectRequest.builder()
              .bucket(bucket)
              .key(objectKey(staged.storageKey()))
              .contentType(content.contentType())
              .contentLength(content.size())
              .build();
      s3Client.putObject(
          request, RequestBody.fromInputStream(content.inputStream(), content.size()));
      return staged;
    } catch (BusinessException exception) {
      throw exception;
    } catch (SdkException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    } catch (java.io.IOException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    } finally {
      cleanupStaging(staged.storageKey());
    }
  }

  /**
   * S3 객체를 메모리에 적재하지 않고 Stream으로 조회한다.
   *
   * @param storageKey DB에 저장된 Prefix 제외 Storage Key
   * @return S3 응답 Stream과 전송 Metadata
   * @throws BusinessException Key가 유효하지 않거나 객체를 조회할 수 없는 경우
   */
  @Override
  public StoredImageContent read(String storageKey) {
    String safeKey = validateStorageKey(storageKey);
    try {
      var response =
          s3Client.getObject(
              GetObjectRequest.builder().bucket(bucket).key(objectKey(safeKey)).build());
      GetObjectResponse metadata = response.response();
      if (metadata.contentType() == null
          || metadata.contentType().isBlank()
          || metadata.contentLength() == null
          || metadata.contentLength() <= 0) {
        response.close();
        throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
      }
      return new StoredImageContent(
          response, metadata.contentType(), metadata.contentLength().longValue());
    } catch (NoSuchKeyException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND);
    } catch (S3Exception exception) {
      if (exception.statusCode() == 404) {
        throw new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND);
      }
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    } catch (SdkException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    } catch (java.io.IOException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    }
  }

  /**
   * S3의 이미지 객체를 삭제한다. S3 DeleteObject의 멱등성을 그대로 사용한다.
   *
   * @param storageKey DB에 저장된 Prefix 제외 Storage Key
   * @throws BusinessException Key가 유효하지 않거나 S3 삭제 요청에 실패한 경우
   */
  @Override
  public void delete(String storageKey) {
    String safeKey = validateStorageKey(storageKey);
    try {
      s3Client.deleteObject(
          DeleteObjectRequest.builder().bucket(bucket).key(objectKey(safeKey)).build());
    } catch (SdkException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    }
  }

  private String objectKey(String storageKey) {
    return prefix + "/" + storageKey;
  }

  private String validateStorageKey(String storageKey) {
    if (storageKey == null
        || storageKey.isBlank()
        || storageKey.indexOf('\\') >= 0
        || storageKey.startsWith("/")) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
    String[] segments = storageKey.split("/", -1);
    for (String segment : segments) {
      if (segment.isBlank() || ".".equals(segment) || "..".equals(segment)) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
      }
    }
    return storageKey;
  }

  private void cleanupStaging(String storageKey) {
    try {
      stagingStorage.delete(storageKey);
    } catch (BusinessException ignored) {
      // Staging 정리 실패가 원래 저장 결과나 S3 오류를 가리지 않도록 한다.
    }
  }
}
