package com.ssafy.b209.child.service;

import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.dto.request.UpdateChildTutorialProgressRequest;
import com.ssafy.b209.child.dto.response.ChildTutorialProgressResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildUpdateRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Objects;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결된 보호자가 아동 Tutorial 진행 상태를 변경하는 Use Case를 수행한다.
 *
 * <p>아동 행을 잠근 뒤 상태 전이를 검증해 동시 요청으로 완료 상태가 되돌아가는 것을 막는다. 완료와 건너뛰기는 종료 상태이며 같은 상태의 재요청만 멱등하게 허용한다.
 */
@Service
public class ChildTutorialService {

  private final ChildUpdateRepository childUpdateRepository;
  private final ChildQueryService childQueryService;
  private final Clock clock;

  /**
   * 운영 시각을 기준으로 Tutorial 상태 변경 서비스를 생성한다.
   *
   * @param childUpdateRepository 아동 행 잠금과 Tutorial 상태 변경 저장소
   * @param childQueryService 변경 결과 조회 Service
   */
  @Autowired
  public ChildTutorialService(
      ChildUpdateRepository childUpdateRepository, ChildQueryService childQueryService) {
    this(childUpdateRepository, childQueryService, Clock.systemUTC());
  }

  ChildTutorialService(
      ChildUpdateRepository childUpdateRepository,
      ChildQueryService childQueryService,
      Clock clock) {
    this.childUpdateRepository = childUpdateRepository;
    this.childQueryService = childQueryService;
    this.clock = clock;
  }

  /**
   * 아동 Tutorial 상태와 마지막 단계를 원자적으로 변경한다.
   *
   * <p>허용 전이는 {@code NOT_STARTED -> IN_PROGRESS -> COMPLETED|SKIPPED}다. 진행 중에는 마지막 단계 저장을 위해 {@code
   * IN_PROGRESS -> IN_PROGRESS}를 허용하며, 종료 상태의 동일 요청은 기존 완료 시각을 유지한 채 현재 상태를 반환한다.
   *
   * @param guardianUserId 변경을 요청한 보호자 사용자 식별자
   * @param childId 변경할 아동 식별자
   * @param request 변경할 Tutorial 상태와 마지막 단계
   * @return 변경 후 Tutorial 진행 상태
   * @throws BusinessException 아동이 없거나 연결되지 않았거나 상태 전이가 허용되지 않는 경우
   */
  @Transactional
  public ChildTutorialProgressResponse updateProgress(
      Long guardianUserId, Long childId, UpdateChildTutorialProgressRequest request) {
    Objects.requireNonNull(request, "request must not be null");
    if (!childUpdateRepository.lockAccessibleChild(guardianUserId, childId)) {
      throw new BusinessException(ChildErrorCode.CHILD_NOT_FOUND);
    }

    ChildTutorialStatus current = childUpdateRepository.findTutorialStatus(childId);
    ChildTutorialStatus target = request.tutorialStatus();
    if (current == target && current != ChildTutorialStatus.IN_PROGRESS) {
      return childQueryService.getTutorialProgress(guardianUserId, childId);
    }
    if (!isAllowedTransition(current, target)) {
      throw new BusinessException(ChildErrorCode.CHILD_TUTORIAL_STATUS_CONFLICT);
    }

    LocalDateTime changedAt = LocalDateTime.now(clock);
    LocalDateTime completedAt =
        target == ChildTutorialStatus.COMPLETED || target == ChildTutorialStatus.SKIPPED
            ? changedAt
            : null;
    childUpdateRepository.updateTutorialProgress(
        childId, target, request.lastStep(), completedAt, changedAt);
    return childQueryService.getTutorialProgress(guardianUserId, childId);
  }

  private boolean isAllowedTransition(ChildTutorialStatus current, ChildTutorialStatus target) {
    return switch (current) {
      case NOT_STARTED -> target == ChildTutorialStatus.IN_PROGRESS;
      case IN_PROGRESS ->
          target == ChildTutorialStatus.IN_PROGRESS
              || target == ChildTutorialStatus.COMPLETED
              || target == ChildTutorialStatus.SKIPPED;
      case COMPLETED, SKIPPED -> false;
    };
  }
}
