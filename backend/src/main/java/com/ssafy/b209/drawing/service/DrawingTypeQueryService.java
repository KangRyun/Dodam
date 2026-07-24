package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.DrawingTypePageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeResponse;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 아동의 연령과 조회 조건에 맞는 그림 활동 유형 목록을 제공한다.
 *
 * <p>인증 사용자와 아동의 연결 관계를 먼저 검증하고, 생년월일은 외부에 노출하지 않은 채 만 나이 계산에만 사용한다.
 */
@Service
@Transactional(readOnly = true)
public class DrawingTypeQueryService {

  private static final Comparator<DrawingType> DISPLAY_ORDER =
      Comparator.comparingInt(DrawingType::getDisplayOrder).thenComparing(DrawingType::getId);

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final ChildRepository childRepository;
  private final DrawingTypeRepository drawingTypeRepository;
  private final Clock clock;

  /**
   * 그림 유형 조회에 필요한 인증·권한·저장소와 기준 시계를 주입받는다.
   *
   * @param currentUserResolver 인증된 사용자 식별자를 제공하는 Resolver
   * @param accessValidator 보호자와 아동의 연결 관계를 검증하는 Validator
   * @param childRepository 연령 계산에 사용할 아동을 조회하는 저장소
   * @param drawingTypeRepository 그림 유형을 조회하는 저장소
   * @param clock 만 나이를 계산할 기준 시계
   */
  public DrawingTypeQueryService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      ChildRepository childRepository,
      DrawingTypeRepository drawingTypeRepository,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.childRepository = childRepository;
    this.drawingTypeRepository = drawingTypeRepository;
    this.clock = clock;
  }

  /**
   * 아동에게 노출할 수 있는 그림 활동 유형을 조회한다.
   *
   * @param childId 그림 유형을 조회할 연결 아동 식별자
   * @param category 조회할 활동 분류, 전체 분류이면 {@code null}
   * @param activeOnly 활성 유형만 포함할지 여부
   * @return 노출 순서가 적용된 그림 유형 단일 페이지
   * @throws BusinessException 인증 사용자가 아동에 접근할 수 없거나 활성 아동을 찾을 수 없는 경우
   */
  public DrawingTypePageResponse getDrawingTypes(
      Long childId, DrawingActivityCategory category, boolean activeOnly) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, childId);
    Child child =
        childRepository
            .findById(childId)
            .filter(Child::isAvailable)
            .orElseThrow(() -> new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));
    int age = child.ageOn(LocalDate.now(clock));

    var responses =
        drawingTypeRepository.findForListing(category, activeOnly).stream()
            .filter(drawingType -> drawingType.isRecommendedForAge(age))
            .sorted(DISPLAY_ORDER)
            .map(DrawingTypeResponse::from)
            .toList();
    return DrawingTypePageResponse.singlePage(responses);
  }
}
