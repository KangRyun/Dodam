package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.request.CanvasConfigurationRequest;
import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.regex.Pattern;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 그림 활동 세션 생성 규칙과 중복 요청 처리를 담당하는 서비스다.
 *
 * <p>아동과 그림 유형의 사용 가능 여부를 확인하고, 아동 단위 잠금과 {@code Idempotency-Key}를 이용해 동시에 여러 세션이 생성되지 않도록 조정한다. 인증
 * 사용자 연결은 후속 인증 기능에서 처리하므로 현재 생성되는 세션의 {@code startedByUserId}는 설정하지 않는다.
 */
@Service
@Transactional(isolation = Isolation.READ_COMMITTED)
public class DrawingSessionService {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;
  private static final int CANVAS_MIN_SIZE = 1;
  private static final int CANVAS_MAX_SIZE = 8192;
  private static final Pattern HEX_COLOR_PATTERN = Pattern.compile("^#[0-9A-Fa-f]{6}$");

  private final ChildRepository childRepository;
  private final DrawingTypeRepository drawingTypeRepository;
  private final DrawingSessionRepository drawingSessionRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final Clock clock;

  /**
   * 그림 활동 세션 생성에 필요한 저장소와 서버 시계를 주입받는다.
   *
   * @param childRepository 아동 조회와 잠금에 사용하는 저장소
   * @param drawingTypeRepository 그림 활동 유형 조회에 사용하는 저장소
   * @param drawingSessionRepository 세션 중복 확인과 저장에 사용하는 저장소
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 아동의 연결 관계를 검증하는 Validator
   * @param clock 나이 계산과 공식 시작 시각 산정에 사용하는 서버 시계
   */
  public DrawingSessionService(
      ChildRepository childRepository,
      DrawingTypeRepository drawingTypeRepository,
      DrawingSessionRepository drawingSessionRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      Clock clock) {
    this.childRepository = childRepository;
    this.drawingTypeRepository = drawingTypeRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.clock = clock;
  }

  /**
   * 유효한 아동과 그림 유형을 기준으로 진행 중 상태의 그림 활동 세션을 생성한다.
   *
   * <p>동일한 {@code Idempotency-Key}와 핵심 요청 값으로 다시 호출하면 기존 세션을 반환한다. 같은 키가 다른 요청에 사용되거나 아동에게 진행 중인
   * 세션이 있으면 충돌 오류가 발생한다. 클라이언트가 보낸 시작 시각은 관측 정보이며, 저장되는 공식 시작 시각은 서버의 UTC 시각이다.
   *
   * @param idempotencyKey 요청 재시도를 식별하는 {@code Idempotency-Key} Header 값
   * @param request 생성할 그림 활동 세션의 아동, 유형, 입력 방식 정보
   * @return 새로 생성했거나 멱등하게 조회한 그림 활동 세션 정보
   * @throws BusinessException 요청 값이 유효하지 않거나 대상이 없거나 생성 충돌이 발생한 경우
   */
  public CreateDrawingSessionResponse createDrawingSession(
      String idempotencyKey, CreateDrawingSessionRequest request) {
    validateIdempotencyKey(idempotencyKey);
    validateCanvas(request);
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, request.childId());

    Optional<DrawingSession> existing =
        drawingSessionRepository.findByIdempotencyKey(idempotencyKey);
    if (existing.isPresent()) {
      return handleExisting(existing.get(), request);
    }

    Child child =
        childRepository
            .findNotDeletedByIdForUpdate(request.childId())
            .filter(Child::isAvailable)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.CHILD_NOT_FOUND));
    existing = drawingSessionRepository.findByIdempotencyKeyForUpdate(idempotencyKey);
    if (existing.isPresent()) {
      return handleExisting(existing.get(), request);
    }
    DrawingType drawingType =
        drawingTypeRepository
            .findById(request.drawingTypeId())
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_TYPE_NOT_FOUND));

    int age = child.ageOn(LocalDate.now(clock));
    if (!drawingType.isAvailableForAge(age)) {
      throw new BusinessException(DrawingErrorCode.DRAWING_TYPE_NOT_AVAILABLE);
    }
    if (drawingSessionRepository.findActiveByChildId(child.getId()).isPresent()) {
      throw new BusinessException(DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS);
    }

    LocalDateTime startedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    DrawingSession session =
        DrawingSession.start(child, drawingType, request.inputMethod(), startedAt, idempotencyKey);
    try {
      return toResponse(drawingSessionRepository.saveAndFlush(session));
    } catch (DataIntegrityViolationException exception) {
      if (isIdempotencyKeyConstraintViolation(exception)) {
        throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT, exception);
      }
      throw new BusinessException(DrawingErrorCode.DRAWING_SESSION_CREATION_CONFLICT, exception);
    }
  }

  private boolean isIdempotencyKeyConstraintViolation(Throwable exception) {
    Throwable current = exception;
    while (current != null) {
      String message = current.getMessage();
      if (message != null && message.contains("uk_drawing_sessions_idempotency_key")) {
        return true;
      }
      current = current.getCause();
    }
    return false;
  }

  private CreateDrawingSessionResponse handleExisting(
      DrawingSession existing, CreateDrawingSessionRequest request) {
    if (!existing.matchesCoreRequest(
        request.childId(), request.drawingTypeId(), request.inputMethod())) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    return toResponse(existing);
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    if (idempotencyKey.length() < IDEMPOTENCY_KEY_MIN_LENGTH
        || idempotencyKey.length() > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.isBlank()
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }

  /**
   * 캔버스 설정을 검증한다.
   *
   * <p>캔버스 물리 크기는 세션 생성 시점에 필수가 아니다. Stroke는 캔버스 크기와 무관한 정규화 좌표로 저장되고 실제 렌더 크기는 스냅샷 업로드 시점에 확정되므로,
   * 클라이언트가 렌더 이전에 정확한 크기를 확보하지 못해도 세션 생성을 막지 않는다. 값을 전달한 경우에만 각 필드의 유효 범위를 확인한다. UPLOAD 방식은 캔버스 설정을
   * 사용하지 않으므로 검증하지 않는다.
   */
  private void validateCanvas(CreateDrawingSessionRequest request) {
    if (request.inputMethod() != DrawingInputMethod.CANVAS) {
      return;
    }
    CanvasConfigurationRequest canvas = request.canvas();
    if (canvas == null) {
      return;
    }
    if (!isCanvasSizeValidOrAbsent(canvas.width())
        || !isCanvasSizeValidOrAbsent(canvas.height())
        || !isBackgroundColorValidOrAbsent(canvas.backgroundColor())) {
      throw new BusinessException(DrawingErrorCode.INVALID_CANVAS_CONFIGURATION);
    }
  }

  private boolean isCanvasSizeValidOrAbsent(Integer size) {
    return size == null || (size >= CANVAS_MIN_SIZE && size <= CANVAS_MAX_SIZE);
  }

  private boolean isBackgroundColorValidOrAbsent(String backgroundColor) {
    return backgroundColor == null || HEX_COLOR_PATTERN.matcher(backgroundColor).matches();
  }

  private CreateDrawingSessionResponse toResponse(DrawingSession session) {
    DrawingType type = session.getDrawingType();
    return new CreateDrawingSessionResponse(
        session.getId(),
        session.getChild().getId(),
        new DrawingTypeSummaryResponse(type.getId(), type.getCode(), type.getName()),
        session.getInputMethod(),
        session.getSessionStatus(),
        session.getCurrentStage(),
        session.getChild().isTutorialRequired(),
        session.getStartedAt().toInstant(ZoneOffset.UTC));
  }
}
