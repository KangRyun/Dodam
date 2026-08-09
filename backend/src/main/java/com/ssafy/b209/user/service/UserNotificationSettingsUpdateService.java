package com.ssafy.b209.user.service;

import com.ssafy.b209.user.dto.request.NotificationSettingsUpdateRequest;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.repository.UserNotificationSettingsRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 로그인 사용자 본인의 알림 수신 설정을 변경한다.
 *
 * <p>요청은 네 값을 모두 담은 전체 교체이므로, 행 존재 여부를 애플리케이션에서 조회·분기하지 않고 저장소의 upsert에 위임한다. 저장 직후 같은 트랜잭션에서 다시 읽어
 * 응답을 만들면 방금 반영한 값이 그대로 보이며, 조회 경로({@link UserNotificationSettingsReader})와 매핑을 공유해 읽기·쓰기 응답이 어긋나지
 * 않는다.
 */
@Service
@Transactional
public class UserNotificationSettingsUpdateService {

  private final UserNotificationSettingsRepository notificationSettingsRepository;
  private final UserNotificationSettingsReader notificationSettingsReader;

  /**
   * 알림 설정 변경기를 구성한다.
   *
   * @param notificationSettingsRepository 알림 설정 저장소
   * @param notificationSettingsReader 저장 후 최신 값을 읽어 응답으로 만드는 조회기
   */
  public UserNotificationSettingsUpdateService(
      UserNotificationSettingsRepository notificationSettingsRepository,
      UserNotificationSettingsReader notificationSettingsReader) {
    this.notificationSettingsRepository = notificationSettingsRepository;
    this.notificationSettingsReader = notificationSettingsReader;
  }

  /**
   * 사용자의 알림 수신 설정을 요청 값으로 저장하고 최신 상태를 반환한다.
   *
   * @param userId 대상 사용자 식별자
   * @param request 저장할 알림 설정 네 값
   * @return 저장 후 최신 알림 수신 설정
   */
  public NotificationSettingsResponse update(
      Long userId, NotificationSettingsUpdateRequest request) {
    notificationSettingsRepository.upsert(
        userId,
        request.analysisCompleted(),
        request.community(),
        request.serviceNotice(),
        request.marketing());
    return notificationSettingsReader.read(userId);
  }
}
