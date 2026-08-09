package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.dto.response.DrawingAssetFileResource;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 보호자가 소유한 그림 파일을 Storage에서 읽을 수 있도록 준비한다.
 *
 * <p>그림 파일 Metadata를 찾은 뒤 소속 그림 활동 세션의 접근 권한을 검증하며, 권한 검증이 끝나기 전에는 Storage를 읽지 않는다. 파일 전송과 Stream
 * 종료는 Controller가 담당한다.
 */
@Service
@Transactional(readOnly = true)
public class DrawingAssetFileQueryService {

  private final DrawingAssetRepository drawingAssetRepository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 그림 파일 조회에 필요한 Metadata, Storage 및 인증 경계를 구성한다.
   *
   * @param drawingAssetRepository 그림 파일 Metadata 조회 Repository
   * @param imageStorage 그림 파일 Stream 조회 경계
   * @param currentUserResolver 현재 인증 사용자 ID Resolver
   * @param accessValidator 보호자와 그림 활동 세션의 연결 관계 Validator
   */
  public DrawingAssetFileQueryService(
      DrawingAssetRepository drawingAssetRepository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingAssetRepository = drawingAssetRepository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 현재 보호자가 접근할 수 있는 그림 파일을 Storage에서 연다.
   *
   * @param drawingAssetId 조회할 그림 파일 식별자
   * @return 응답 전송 후 닫아야 하는 그림 파일 Resource
   * @throws BusinessException 인증 정보가 없거나, 그림 파일 또는 접근 가능한 그림 활동을 찾을 수 없는 경우
   */
  public DrawingAssetFileResource getFile(Long drawingAssetId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    DrawingAsset drawingAsset =
        drawingAssetRepository
            .findById(drawingAssetId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_ASSET_NOT_FOUND));
    accessValidator.requireDrawingSessionAccess(
        guardianUserId, drawingAsset.getDrawingSession().getId());
    return new DrawingAssetFileResource(imageStorage.read(drawingAsset.getStorageKey()));
  }
}
