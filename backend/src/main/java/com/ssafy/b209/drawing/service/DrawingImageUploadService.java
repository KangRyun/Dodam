package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.UploadDrawingImageRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingImageResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * HTP 단계에서 사진 또는 기존 이미지로 시작할 때 원본 파일을 검증하고 저장한다.
 *
 * <p>일반 그림일기와 Canvas 세션에는 이 경계를 열지 않는다. HTP 단계 연결에서 주제를 결정하고, 동일한 {@code Idempotency-Key} 재시도에는 같은
 * Asset을 반환한다. 파일 저장 후 DB 반영이 실패하면 생성된 파일을 보상 삭제한다.
 */
@Service
@Transactional
public class DrawingImageUploadService {

  private static final Logger log = LoggerFactory.getLogger(DrawingImageUploadService.class);
  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;
  private static final List<Integer> ALLOWED_ROTATIONS = List.of(0, 90, 180, 270);

  private final DrawingSessionRepository sessionRepository;
  private final DrawingAssetRepository assetRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final DrawingAssetFileUrlFactory fileUrlFactory;
  private final Clock clock;

  /**
   * HTP 이미지 업로드에 필요한 저장소와 인증·Storage 경계를 주입받는다.
   *
   * @param sessionRepository 잠금 세션 조회 저장소
   * @param assetRepository 업로드 Asset 저장소
   * @param htpAssessmentRepository 세션의 HTP 주제 조회 저장소
   * @param imageStorage 이미지 검증·정규화 저장소
   * @param currentUserResolver 현재 보호자 식별자 Resolver
   * @param accessValidator 보호자와 세션의 접근 관계 검증기
   * @param fileUrlFactory 인증 파일 조회 URL 생성기
   * @param clock 서버 수신·저장 시각 기준
   */
  public DrawingImageUploadService(
      DrawingSessionRepository sessionRepository,
      DrawingAssetRepository assetRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      DrawingAssetFileUrlFactory fileUrlFactory,
      Clock clock) {
    this.sessionRepository = sessionRepository;
    this.assetRepository = assetRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.fileUrlFactory = fileUrlFactory;
    this.clock = clock;
  }

  /**
   * UPLOAD 방식 HTP 단계에 검증된 원본 이미지 한 장을 저장한다.
   *
   * @param drawingSessionId HTP HOUSE·TREE·PERSON 단계 세션 식별자
   * @param idempotencyKey 동일 요청의 재시도를 식별하는 Header 값
   * @param image JPEG 또는 PNG 입력 Stream
   * @param request 촬영 시각과 회전·자르기 Metadata
   * @return 완료 요청의 {@code sourceAssetId}와 인증 미리보기 URL을 포함한 저장 결과
   * @throws BusinessException 요청, 접근 권한, 세션 상태, 중복 또는 저장이 유효하지 않은 경우
   */
  public UploadDrawingImageResponse upload(
      Long drawingSessionId,
      String idempotencyKey,
      StoreImageCommand image,
      UploadDrawingImageRequest request) {
    validateRequest(idempotencyKey, image, request);
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    DrawingSession session =
        sessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    Optional<DrawingAsset> previous = assetRepository.findByUploadIdempotencyKey(idempotencyKey);
    HtpAssessmentStep step = requireUploadHtpStep(session);

    if (previous.isEmpty()) {
      requireUploadable(session);
      if (assetRepository.existsByDrawingSessionIdAndAssetType(
          drawingSessionId, DrawingAssetType.UPLOADED)) {
        throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_ALREADY_EXISTS);
      }
    }

    StoredImage storedImage = imageStorage.store(image);
    String fingerprint =
        fingerprint(guardianUserId, drawingSessionId, storedImage.checksumSha256(), request);
    if (previous.isPresent()) {
      compensate(storedImage.storageKey(), drawingSessionId);
      DrawingAsset existing = previous.get();
      if (!Objects.equals(existing.getDrawingSession().getId(), drawingSessionId)
          || !Objects.equals(existing.getUploadFingerprint(), fingerprint)) {
        throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT);
      }
      return toResponse(existing, step);
    }

    LocalDateTime uploadedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    LocalDateTime capturedAt =
        request.clientCapturedAt() == null
            ? uploadedAt
            : request.clientCapturedAt().withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime();
    DrawingAsset asset =
        DrawingAsset.uploaded(
            session,
            storedImage.storageKey(),
            storedImage.contentType(),
            storedImage.size(),
            storedImage.widthPx(),
            storedImage.heightPx(),
            storedImage.checksumSha256(),
            capturedAt,
            uploadedAt,
            idempotencyKey,
            fingerprint,
            request.rotationDegrees(),
            request.cropApplied());
    try {
      return toResponse(assetRepository.saveAndFlush(asset), step);
    } catch (RuntimeException exception) {
      compensate(storedImage.storageKey(), drawingSessionId);
      if (exception instanceof DataIntegrityViolationException) {
        throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_ALREADY_EXISTS, exception);
      }
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_FAILED, exception);
    }
  }

  private HtpAssessmentStep requireUploadHtpStep(DrawingSession session) {
    if (session.getInputMethod() != DrawingInputMethod.UPLOAD) {
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_NOT_SUPPORTED);
    }
    return htpAssessmentRepository
        .findStepByDrawingSessionId(session.getId())
        .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_NOT_SUPPORTED));
  }

  private void requireUploadable(DrawingSession session) {
    if (!session.isSnapshotUploadable()) {
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_NOT_ALLOWED);
    }
  }

  private void validateRequest(
      String idempotencyKey, StoreImageCommand image, UploadDrawingImageRequest request) {
    if (idempotencyKey == null) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    if (idempotencyKey.isBlank()
        || idempotencyKey.length() < IDEMPOTENCY_KEY_MIN_LENGTH
        || idempotencyKey.length() > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
    if (image == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_FILE_REQUIRED);
    }
    if (request == null
        || request.cropApplied() == null
        || !ALLOWED_ROTATIONS.contains(request.rotationDegrees())) {
      throw new BusinessException(DrawingErrorCode.DRAWING_UPLOAD_METADATA_INVALID);
    }
  }

  private String fingerprint(
      Long guardianUserId,
      Long drawingSessionId,
      String checksumSha256,
      UploadDrawingImageRequest request) {
    String capturedAt =
        request.clientCapturedAt() == null ? "" : request.clientCapturedAt().toInstant().toString();
    String canonical =
        guardianUserId
            + "|"
            + drawingSessionId
            + "|"
            + checksumSha256
            + "|"
            + capturedAt
            + "|"
            + request.rotationDegrees()
            + "|"
            + request.cropApplied();
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256")
                  .digest(canonical.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is not available", exception);
    }
  }

  private UploadDrawingImageResponse toResponse(DrawingAsset asset, HtpAssessmentStep step) {
    return new UploadDrawingImageResponse(
        asset.getDrawingSession().getId(),
        asset.getId(),
        asset.getAssetType(),
        step.getDrawingSubject(),
        asset.getDrawingSession().getCurrentStage(),
        fileUrlFactory.create(asset.getId()),
        asset.getMimeType(),
        asset.getFileSizeBytes(),
        asset.getWidthPx(),
        asset.getHeightPx(),
        asset.getCapturedAt().toInstant(ZoneOffset.UTC),
        asset.getCreatedAt().toInstant(ZoneOffset.UTC),
        List.of());
  }

  private void compensate(String storageKey, Long drawingSessionId) {
    try {
      imageStorage.delete(storageKey);
    } catch (RuntimeException cleanupException) {
      log.warn(
          "HTP 원본 이미지 Metadata 저장 실패 후 파일 보상 삭제에 실패했습니다. drawingSessionId={}", drawingSessionId);
    }
  }
}
