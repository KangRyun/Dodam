package com.ssafy.b209.child.service;

import com.ssafy.b209.child.dto.request.DeleteChildRequest;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결된 아동 프로필을 비활성화하고 연관 파일 삭제를 예약하는 Use Case다.
 *
 * <p>현재 DB에는 주 보호자 구분이 없으므로 요청자가 유일한 연결 보호자인 경우에만 전체 삭제를 허용한다. 여러 보호자가 연결된 아동은 데이터 손실을 막기 위해 삭제를
 * 거부한다.
 */
@Service
public class ChildDeletionService {

  private static final String CONFIRMATION = "DELETE";

  private final ChildDeletionRepository childDeletionRepository;
  private final Clock clock;

  /**
   * 운영 시각을 기준으로 아동 삭제 서비스를 생성한다.
   *
   * @param childDeletionRepository 아동 상태 변경과 Storage 삭제 예약 저장소
   */
  @Autowired
  public ChildDeletionService(ChildDeletionRepository childDeletionRepository) {
    this(childDeletionRepository, Clock.systemUTC());
  }

  ChildDeletionService(ChildDeletionRepository childDeletionRepository, Clock clock) {
    this.childDeletionRepository = childDeletionRepository;
    this.clock = clock;
  }

  /**
   * 확인 문자열과 보호자 관계를 검증한 뒤 아동 프로필을 Soft Delete한다.
   *
   * <p>본문 누락, 공백, {@code DELETE} 이외의 값은 모두 같은 확인 값 오류로 처리한다. 클라이언트가 오작동 방지 장치를 우회했는지를 한 가지 응답으로 알 수
   * 있어야 하므로 요청 형태에 따라 오류를 나누지 않는다.
   *
   * @param guardianUserId 삭제를 요청한 인증 보호자 사용자 ID
   * @param childId 삭제할 아동 ID
   * @param request 명시적 삭제 확인 요청이며 본문이 없으면 {@code null}
   * @throws BusinessException 확인 문자열이 없거나 다르거나, 접근할 수 없거나, 다른 보호자가 연결된 경우
   */
  @Transactional
  public void delete(Long guardianUserId, Long childId, DeleteChildRequest request) {
    if (request == null || !CONFIRMATION.equals(request.confirmation())) {
      throw new BusinessException(ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH);
    }
    if (!childDeletionRepository.lockAccessibleChild(guardianUserId, childId)) {
      throw new BusinessException(ChildErrorCode.CHILD_NOT_FOUND);
    }
    if (childDeletionRepository.countGuardians(childId) > 1) {
      throw new BusinessException(ChildErrorCode.CHILD_HAS_OTHER_GUARDIAN);
    }

    LocalDateTime deletedAt = LocalDateTime.now(clock);
    childDeletionRepository.markDeleted(childId, deletedAt);
    childDeletionRepository.scheduleStorageDeletions(childId);
  }
}
