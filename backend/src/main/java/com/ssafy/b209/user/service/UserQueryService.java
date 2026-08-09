package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 사용자가 자신의 현재 계정 상태를 조회하는 Use Case를 제공한다. */
@Service
@Transactional(readOnly = true)
public class UserQueryService {

  private final UserRepository userRepository;
  private final UserNotificationSettingsReader notificationSettingsReader;

  /**
   * 사용자 조회 서비스를 구성한다.
   *
   * @param userRepository 사용자 저장소
   * @param notificationSettingsReader 알림 수신 설정 조회기
   */
  public UserQueryService(
      UserRepository userRepository, UserNotificationSettingsReader notificationSettingsReader) {
    this.userRepository = userRepository;
    this.notificationSettingsReader = notificationSettingsReader;
  }

  /**
   * 인증 사용자의 현재 상태를 반환한다.
   *
   * @param userId 인증된 사용자 식별자
   * @return 사용자 본인 상태
   * @throws BusinessException 사용자를 찾을 수 없는 경우
   */
  public UserResponse getMe(Long userId) {
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));
    return UserResponseMapper.toResponse(user, notificationSettingsReader.read(userId));
  }
}
