package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCanvasStateResponse;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
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
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 진행 중인 그림 활동의 초안 미리보기 저장과 최신 Metadata 조회를 담당한다.
 *
 * <p>세션 쓰기 잠금과 마지막 이벤트 순서를 함께 사용해 늦게 도착한 이전 이미지가 최신 초안이 되는 것을 방지한다. 파일 저장 후 DB 반영이 실패하면 {@link
 * ImageStorage}를 통해 새 파일을 보상 삭제한다.
 */
@Slf4j
@Service
public class DrawingDraftService {

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final Clock clock;

  /**
   * 초안 저장에 필요한 세션·파일 Metadata 의존성을 구성한다.
   *
   * @param drawingSessionRepository 세션 조회와 잠금 Repository
   * @param drawingAssetRepository 초안 Metadata Repository
   * @param imageStorage 검증된 이미지 저장과 보상 삭제 경계
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계를 검증하는 Validator
   * @param clock 서버 저장 시각을 제공하는 Clock
   */
  public DrawingDraftService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      Clock clock) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.clock = clock;
  }

  /**
   * 진행 중인 DRAWING 단계 세션에 현재 캔버스 미리보기를 새 초안 버전으로 저장한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param preview 현재 캔버스 미리보기 이미지
   * @param request 미리보기에 반영된 마지막 이벤트 순서와 클라이언트 저장 시각
   * @return 내부 저장 경로를 제외한 저장 결과
   * @throws BusinessException 세션·요청이 유효하지 않거나 이전 초안 또는 저장 충돌인 경우
   */
  @Transactional
  public DrawingDraftResponse save(
      Long drawingSessionId, StoreImageCommand preview, SaveDrawingDraftRequest request) {
    validate(preview, request);
    requireAccess(drawingSessionId);
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!session.isSnapshotUploadable()) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_NOT_ALLOWED);
    }

    Optional<DrawingAsset> latest = drawingAssetRepository.findLatestDraft(drawingSessionId);
    rejectStaleSequence(latest, request.lastEventSequence());
    int nextVersion = latest.map(asset -> asset.getAssetVersion() + 1).orElse(1);
    StoredImage storedImage = imageStorage.store(preview);
    LocalDateTime savedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    DrawingAsset draft =
        DrawingAsset.draft(
            session,
            nextVersion,
            storedImage.storageKey(),
            storedImage.contentType(),
            storedImage.size(),
            storedImage.checksumSha256(),
            request.lastEventSequence(),
            request.clientSavedAt().withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime(),
            savedAt);
    try {
      return toResponse(drawingAssetRepository.saveAndFlush(draft));
    } catch (RuntimeException exception) {
      compensate(storedImage.storageKey(), drawingSessionId);
      if (exception instanceof DataIntegrityViolationException) {
        throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_SAVE_CONFLICT, exception);
      }
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_STORAGE_FAILED, exception);
    }
  }

  /**
   * 삭제되지 않은 세션에 저장된 가장 높은 버전의 초안 Metadata를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 최신 초안 Metadata
   * @throws BusinessException 세션 또는 저장된 초안을 찾을 수 없는 경우
   */
  @Transactional(readOnly = true)
  public DrawingDraftResponse getLatest(Long drawingSessionId) {
    requireAccess(drawingSessionId);
    drawingSessionRepository
        .findNotDeletedById(drawingSessionId)
        .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    DrawingAsset draft =
        drawingAssetRepository
            .findLatestDraft(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_DRAFT_NOT_FOUND));
    return toResponse(draft);
  }

  private void requireAccess(Long drawingSessionId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
  }

  private void validate(StoreImageCommand preview, SaveDrawingDraftRequest request) {
    if (preview == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_FILE_REQUIRED);
    }
    if (request == null || request.lastEventSequence() <= 0 || request.clientSavedAt() == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_METADATA_INVALID);
    }
  }

  private void rejectStaleSequence(Optional<DrawingAsset> latest, long requestedSequence) {
    if (latest.isEmpty()) {
      return;
    }
    long latestSequence = latest.orElseThrow().getLastEventSequence();
    if (requestedSequence == latestSequence) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DRAFT_VERSION_CONFLICT);
    }
    if (requestedSequence < latestSequence) {
      throw new BusinessException(DrawingErrorCode.STALE_DRAWING_DRAFT_VERSION);
    }
  }

  private void compensate(String storageKey, Long drawingSessionId) {
    try {
      imageStorage.delete(storageKey);
    } catch (RuntimeException cleanupException) {
      log.warn("초안 Metadata 저장 실패 후 파일 보상 삭제에 실패했습니다. drawingSessionId={}", drawingSessionId);
    }
  }

  private DrawingDraftResponse toResponse(DrawingAsset asset) {
    return new DrawingDraftResponse(
        asset.getId(),
        asset.getDrawingSession().getId(),
        asset.getAssetType(),
        asset.getAssetVersion(),
        asset.getLastEventSequence(),
        false,
        asset.getMimeType(),
        asset.getFileSizeBytes(),
        asset.getCapturedAt().toInstant(ZoneOffset.UTC),
        asset.getCreatedAt().toInstant(ZoneOffset.UTC),
        null,
        null,
        new DrawingCanvasStateResponse(
            asset.getLastEventSequence(), asset.getCapturedAt().toInstant(ZoneOffset.UTC)));
  }
}
