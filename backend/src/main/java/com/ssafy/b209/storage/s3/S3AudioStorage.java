package com.ssafy.b209.storage.s3;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageErrorCode;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import com.ssafy.b209.storage.audio.StoredAudioContent;
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
 * 검증된 음성 파일을 S3 호환 Object Storage에 저장하는 {@link AudioStorage} 구현체다.
 *
 * <p>형식과 재생 시간 검증은 기존 {@link LocalAudioStorage}에 위임하고, 검증을 통과한 파일만 {@code audio/} Prefix에 업로드한다.
 */
public final class S3AudioStorage implements AudioStorage {

  private final S3Client s3Client;
  private final String bucket;
  private final String prefix;
  private final LocalAudioStorage stagingStorage;

  /**
   * S3 음성 저장소를 생성한다.
   *
   * @param s3Client S3 호환 API Client
   * @param properties Bucket과 음성 Prefix 설정
   * @param stagingStorage 음성 검증과 Local staging을 담당하는 저장소
   */
  public S3AudioStorage(
      S3Client s3Client, S3StorageProperties properties, LocalAudioStorage stagingStorage) {
    this(s3Client, properties, properties.audioPrefix(), stagingStorage);
  }

  /**
   * 용도별 Prefix를 지정하는 S3 음성 저장소를 생성한다.
   *
   * <p>아동 음성 원본과 재생성 가능한 TTS 캐시가 서로 다른 보존 정책을 따를 때 사용한다.
   *
   * @param s3Client S3 호환 API Client
   * @param properties Bucket 설정
   * @param prefix 이 저장소가 전용으로 사용할 정규화된 Prefix
   * @param stagingStorage 음성 검증과 Local staging을 담당하는 저장소
   */
  public S3AudioStorage(
      S3Client s3Client,
      S3StorageProperties properties,
      String prefix,
      LocalAudioStorage stagingStorage) {
    this.s3Client = Objects.requireNonNull(s3Client, "s3Client must not be null");
    S3StorageProperties requiredProperties =
        Objects.requireNonNull(properties, "properties must not be null");
    this.bucket = requiredProperties.bucket();
    if (prefix == null || prefix.isBlank()) {
      throw new IllegalArgumentException("audio prefix must not be blank");
    }
    this.prefix = prefix;
    this.stagingStorage = Objects.requireNonNull(stagingStorage, "stagingStorage must not be null");
  }

  /** {@inheritDoc} */
  @Override
  public StagedAudio stage(StoreAudioCommand command) {
    return stagingStorage.stage(command);
  }

  /**
   * 검증된 Local staging 파일을 S3에 업로드하고 Local 파일을 정리한다.
   *
   * @param stagedAudio {@link #stage(StoreAudioCommand)}가 반환한 검증 완료 파일
   * @return DB에 저장할 Prefix 제외 Storage Key와 음성 Metadata
   * @throws BusinessException 음성이 유효하지 않거나 S3 업로드에 실패한 경우
   */
  @Override
  public StoredAudio promote(StagedAudio stagedAudio) {
    StoredAudio staged = stagingStorage.promote(stagedAudio);
    try (StoredAudioContent content = stagingStorage.read(staged.storageKey())) {
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
    } catch (SdkException | java.io.IOException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED, exception);
    } finally {
      cleanupStaging(staged.storageKey());
    }
  }

  /** {@inheritDoc} */
  @Override
  public void discard(StagedAudio stagedAudio) {
    stagingStorage.discard(stagedAudio);
  }

  /**
   * S3의 음성 객체를 메모리에 적재하지 않고 Stream으로 조회한다.
   *
   * @param storageKey DB에 저장된 Prefix 제외 Storage Key
   * @return S3 응답 Stream과 전송 Metadata
   * @throws BusinessException Key가 유효하지 않거나 객체를 조회할 수 없는 경우
   */
  @Override
  public StoredAudioContent read(String storageKey) {
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
        throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
      }
      return new StoredAudioContent(
          response, metadata.contentType(), metadata.contentLength().longValue());
    } catch (NoSuchKeyException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
    } catch (S3Exception exception) {
      if (exception.statusCode() == 404) {
        throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
      }
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED, exception);
    } catch (SdkException | java.io.IOException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED, exception);
    }
  }

  /**
   * S3의 음성 객체를 삭제한다.
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
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED, exception);
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
      throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
    }
    String[] segments = storageKey.split("/", -1);
    for (String segment : segments) {
      if (segment.isBlank() || ".".equals(segment) || "..".equals(segment)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
    }
    return storageKey;
  }

  private void cleanupStaging(String storageKey) {
    try {
      stagingStorage.delete(storageKey);
    } catch (BusinessException ignored) {
      // Staging 정리 실패가 원래 업로드 결과나 S3 오류를 가리지 않도록 한다.
    }
  }
}
