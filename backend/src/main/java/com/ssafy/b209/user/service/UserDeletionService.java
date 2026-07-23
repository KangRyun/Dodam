package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증 사용자의 계정 식별정보를 즉시 삭제하는 회원 탈퇴 Use Case다.
 *
 * <p>사용자 FK의 CASCADE·SET NULL 정책에 따라 인증 계정과 개인 설정은 함께 제거하고, 감사·활동 기록의 사용자 참조는 비식별화한다. 아동 및 활동 데이터
 * 삭제는 별도 API 정책으로 분리한다.
 */
@Service
public class UserDeletionService {

  private static final String CONFIRMATION = "DELETE";

  private final UserRepository userRepository;

  /**
   * 회원 탈퇴 서비스를 구성한다.
   *
   * @param userRepository 사용자 존재 확인과 hard delete를 수행할 저장소
   */
  public UserDeletionService(UserRepository userRepository) {
    this.userRepository = userRepository;
  }

  /**
   * 확인 문자열을 검증하고 인증 사용자를 즉시 삭제한다.
   *
   * @param userId Access Token으로 인증된 사용자 ID
   * @param request 탈퇴 확인 요청
   * @throws BusinessException 확인 문자열이 다르거나 사용자가 존재하지 않는 경우
   */
  @Transactional
  public void delete(Long userId, DeleteUserRequest request) {
    if (!CONFIRMATION.equals(request.confirmation())) {
      throw new BusinessException(UserErrorCode.WITHDRAWAL_CONFIRMATION_MISMATCH);
    }
    if (!userRepository.existsById(userId)) {
      throw new BusinessException(UserErrorCode.USER_NOT_FOUND);
    }
    userRepository.deleteById(userId);
  }
}
