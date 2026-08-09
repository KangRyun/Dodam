package com.ssafy.b209.infrastructure.ai.image;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.net.URI;
import java.util.Objects;
import org.springframework.dao.DataAccessException;

/**
 * 그림 분석 요청용 일회성 이미지 URL을 발급하고 최초 조회에만 저장 이미지를 제공한다.
 *
 * <p>URL에는 Storage Key나 파일 경로를 포함하지 않는다. Token의 만료·재사용과 이미지 누락 여부는 동일한 404로 처리하여 내부 저장 상태를 노출하지
 * 않는다.
 */
public final class AiImageAccessService {

  private static final String INTERNAL_IMAGE_PATH = "/internal/v1/ai-images/";

  private final AiImageAccessTokenStore tokenStore;
  private final ImageStorage imageStorage;
  private final AiImageAccessProperties properties;

  /**
   * 일회성 이미지 조회 Use Case를 구성한다.
   *
   * @param tokenStore Token 발급과 원자적 소비 저장소
   * @param imageStorage 원본 이미지 Storage 경계
   * @param properties 내부 Base URL과 Token TTL
   */
  public AiImageAccessService(
      AiImageAccessTokenStore tokenStore,
      ImageStorage imageStorage,
      AiImageAccessProperties properties) {
    this.tokenStore = Objects.requireNonNull(tokenStore, "tokenStore must not be null");
    this.imageStorage = Objects.requireNonNull(imageStorage, "imageStorage must not be null");
    this.properties = Objects.requireNonNull(properties, "properties must not be null");
  }

  /**
   * Storage Key를 노출하지 않는 짧은 수명의 일회성 내부 URL을 발급한다.
   *
   * @param storageKey 분석 대상 이미지의 상대 Storage Key
   * @return AI 서버가 최초 한 번만 조회할 수 있는 내부 URL
   * @throws DrawingAnalysisClientException Redis에서 Token을 발급할 수 없는 경우
   */
  public URI createReadUrl(String storageKey) {
    try {
      String token = tokenStore.issue(storageKey, properties.tokenTtl());
      return URI.create(properties.internalBaseUrl() + INTERNAL_IMAGE_PATH + token);
    } catch (DataAccessException | IllegalStateException | IllegalArgumentException exception) {
      throw new DrawingAnalysisClientException(
          DrawingAnalysisClientException.Type.REQUEST_FAILED, exception);
    }
  }

  /**
   * Token을 소비하고 연결된 이미지 Stream을 조회한다.
   *
   * @param token URL 경로로 전달된 일회성 Token
   * @return Content-Type과 크기를 포함한 이미지 Stream
   * @throws BusinessException Token이 유효하지 않거나 이미지가 없거나 Infrastructure가 불가용한 경우
   */
  public StoredImageContent consume(String token) {
    String storageKey;
    try {
      storageKey =
          tokenStore
              .consume(token)
              .orElseThrow(
                  () -> new BusinessException(AiImageAccessErrorCode.IMAGE_ACCESS_NOT_FOUND));
    } catch (DataAccessException exception) {
      throw new BusinessException(AiImageAccessErrorCode.IMAGE_ACCESS_UNAVAILABLE, exception);
    }

    try {
      return imageStorage.read(storageKey);
    } catch (BusinessException exception) {
      if (exception.getErrorCode() == ImageStorageErrorCode.IMAGE_NOT_FOUND
          || exception.getErrorCode() == ImageStorageErrorCode.INVALID_STORAGE_PATH) {
        throw new BusinessException(AiImageAccessErrorCode.IMAGE_ACCESS_NOT_FOUND);
      }
      if (exception.getErrorCode() == ImageStorageErrorCode.IMAGE_STORAGE_FAILED) {
        throw new BusinessException(AiImageAccessErrorCode.IMAGE_ACCESS_UNAVAILABLE, exception);
      }
      throw exception;
    }
  }
}
