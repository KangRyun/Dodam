package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.UploadDrawingSnapshotRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 그림 활동 세션의 스냅샷 업로드 규칙과 파일·Metadata 저장의 일관성을 관리한다.
 *
 * <p>파일 저장 후 DB 저장이 실패하면 이번 요청에서 생성한 파일을 보상 삭제한다. 업로드만으로 세션 상태를 변경하거나 AI 분석을 실행하지 않는다.
 */
@Service
@Transactional
public class DrawingSnapshotService {

  private static final Logger log = LoggerFactory.getLogger(DrawingSnapshotService.class);

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final ImageStorage imageStorage;
  private final Clock clock;

  /**
   * 스냅샷 업로드에 필요한 저장소와 서버 시계를 주입받는다.
   *
   * @param drawingSessionRepository 세션 조회와 잠금에 사용하는 저장소
   * @param drawingAssetRepository 중복 확인과 Metadata 저장에 사용하는 저장소
   * @param imageStorage 이미지 검증·저장과 보상 삭제를 담당하는 저장소
   * @param clock 서버 저장 시각을 결정하는 시계
   */
  public DrawingSnapshotService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      ImageStorage imageStorage,
      Clock clock) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.imageStorage = imageStorage;
    this.clock = clock;
  }

  /**
   * 업로드 가능한 세션에 이미지 파일을 저장하고 해당 Metadata를 생성한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param file 이미지 Stream과 전송 Metadata
   * @param request 스냅샷 유형, 버전과 캡처 시각
   * @return 내부 경로를 제외한 저장 결과
   * @throws BusinessException 세션·요청·파일이 유효하지 않거나 저장이 충돌 또는 실패한 경우
   */
  public UploadDrawingSnapshotResponse upload(
      Long drawingSessionId, StoreImageCommand file, UploadDrawingSnapshotRequest request) {
    validateRequest(file, request);
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!session.isSnapshotUploadable()) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_UPLOADABLE);
    }
    rejectDuplicates(drawingSessionId, request);

    StoredImage storedImage = imageStorage.store(file);
    LocalDateTime uploadedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    DrawingAsset asset =
        DrawingAsset.snapshot(
            session,
            request.assetType(),
            request.assetVersion(),
            storedImage.storageKey(),
            storedImage.contentType(),
            storedImage.size(),
            storedImage.checksumSha256(),
            request.capturedAt().withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime(),
            uploadedAt);
    try {
      return toResponse(drawingAssetRepository.saveAndFlush(asset));
    } catch (RuntimeException exception) {
      compensate(storedImage.storageKey(), drawingSessionId);
      if (exception instanceof DataIntegrityViolationException) {
        throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_CREATION_CONFLICT, exception);
      }
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_STORAGE_FAILED, exception);
    }
  }

  private void validateRequest(StoreImageCommand file, UploadDrawingSnapshotRequest request) {
    if (file == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_FILE_REQUIRED);
    }
    if (request == null
        || request.assetType() == null
        || !request.assetType().isSnapshotUploadType()
        || request.assetVersion() == null
        || request.assetVersion() <= 0
        || request.capturedAt() == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_METADATA_INVALID);
    }
  }

  private void rejectDuplicates(Long drawingSessionId, UploadDrawingSnapshotRequest request) {
    if (drawingAssetRepository.existsByDrawingSessionIdAndAssetTypeAndAssetVersion(
        drawingSessionId, request.assetType(), request.assetVersion())) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_SEQUENCE_CONFLICT);
    }
    if (request.assetType() == DrawingAssetType.FINAL
        && drawingAssetRepository.existsByDrawingSessionIdAndAssetType(
            drawingSessionId, DrawingAssetType.FINAL)) {
      throw new BusinessException(DrawingErrorCode.DRAWING_FINAL_SNAPSHOT_EXISTS);
    }
  }

  private void compensate(String storageKey, Long drawingSessionId) {
    try {
      imageStorage.delete(storageKey);
    } catch (RuntimeException cleanupException) {
      log.warn("스냅샷 Metadata 저장 실패 후 파일 보상 삭제에 실패했습니다. drawingSessionId={}", drawingSessionId);
    }
  }

  private UploadDrawingSnapshotResponse toResponse(DrawingAsset asset) {
    return new UploadDrawingSnapshotResponse(
        asset.getId(),
        asset.getDrawingSession().getId(),
        asset.getAssetType(),
        asset.getAssetVersion(),
        asset.getMimeType(),
        asset.getFileSizeBytes(),
        asset.getChecksumSha256(),
        asset.getCapturedAt().toInstant(ZoneOffset.UTC),
        asset.getCreatedAt().toInstant(ZoneOffset.UTC));
  }
}
