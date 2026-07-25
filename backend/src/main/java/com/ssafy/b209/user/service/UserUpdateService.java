package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.UpdateUserRequest;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 로그인 사용자가 본인 프로필의 변경 가능한 필드를 수정하는 Use Case를 제공한다.
 *
 * <p>전달된 필드만 반영하며 프로필 이미지 연결은 사전 업로드 기반이 마련되기 전까지 반영하지 않는다.
 */
@Service
public class UserUpdateService {

  private final UserRepository userRepository;
  private final UserNotificationSettingsReader notificationSettingsReader;
  private final Clock clock;

  /**
   * 사용자 수정 서비스를 구성한다.
   *
   * @param userRepository 사용자 저장소
   * @param notificationSettingsReader 알림 수신 설정 조회기
   */
  @Autowired
  public UserUpdateService(
      UserRepository userRepository, UserNotificationSettingsReader notificationSettingsReader) {
    this(userRepository, notificationSettingsReader, Clock.systemUTC());
  }

  UserUpdateService(
      UserRepository userRepository,
      UserNotificationSettingsReader notificationSettingsReader,
      Clock clock) {
    this.userRepository = userRepository;
    this.notificationSettingsReader = notificationSettingsReader;
    this.clock = clock;
  }

  /**
   * 인증 사용자의 프로필을 부분 수정한다.
   *
   * @param userId 인증된 사용자 식별자
   * @param request 변경할 필드
   * @return 수정 후 사용자 상태
   * @throws BusinessException 사용자를 찾을 수 없는 경우
   */
  @Transactional
  public UserResponse updateProfile(Long userId, UpdateUserRequest request) {
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));

    if (request.nickname() != null) {
      user.changeNickname(request.nickname(), LocalDateTime.now(clock));
      userRepository.save(user);
    }

    return UserResponseMapper.toResponse(user, notificationSettingsReader.read(userId));
  }
}
