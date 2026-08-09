package com.ssafy.b209.auth.authorization;

import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증된 보호자가 연결 아동과 그 아동의 그림 활동에 접근할 수 있는지 검증한다. */
@Service
@Transactional(readOnly = true)
public class GuardianResourceAccessValidator {

  private final GuardianResourceAccessRepository repository;

  /**
   * 보호자 소유 자원 관계를 조회하는 Validator를 생성한다.
   *
   * @param repository 개인정보를 반환하지 않고 관계 존재 여부만 조회하는 Repository
   */
  public GuardianResourceAccessValidator(GuardianResourceAccessRepository repository) {
    this.repository = repository;
  }

  /**
   * 보호자가 지정 아동에 접근할 수 있는지 확인한다.
   *
   * <p>권한 없음과 자원 없음에 같은 오류를 사용해 아동 식별자 존재 여부를 노출하지 않는다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 접근 대상 아동 식별자
   * @throws BusinessException 연결된 활성 아동을 찾을 수 없는 경우
   */
  public void requireChildAccess(Long guardianUserId, Long childId) {
    if (!repository.hasChildAccess(guardianUserId, childId)) {
      throw new BusinessException(ChildErrorCode.CHILD_NOT_FOUND);
    }
  }

  /**
   * 보호자가 지정 그림 활동에 접근할 수 있는지 확인한다.
   *
   * <p>권한 없음과 자원 없음에 같은 오류를 사용해 그림 활동 식별자 존재 여부를 노출하지 않는다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param drawingSessionId 접근 대상 그림 활동 식별자
   * @throws BusinessException 연결된 아동의 접근 가능한 그림 활동을 찾을 수 없는 경우
   */
  public void requireDrawingSessionAccess(Long guardianUserId, Long drawingSessionId) {
    if (!repository.hasDrawingSessionAccess(guardianUserId, drawingSessionId)) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);
    }
  }
}
