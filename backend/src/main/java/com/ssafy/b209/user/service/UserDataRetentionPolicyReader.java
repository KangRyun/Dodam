package com.ssafy.b209.user.service;

import com.ssafy.b209.user.dto.response.DataRetentionPolicyResponse;
import com.ssafy.b209.user.repository.UserDataRetentionSettingsRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 사용자에게 적용 중인 데이터 보관 정책을 조회한다.
 *
 * <p>사용자마다 {@code user_data_retention_settings} 행이 항상 존재한다고 보장할 수 없으므로, 행이 없으면 컬럼 DEFAULT와 동일한 기본값을
 * 반환해 조회가 404로 갈리지 않게 한다. 알림 설정 조회({@link UserNotificationSettingsReader})와 같은 규약이다.
 *
 * <p>보관 만료 임박 알림 스케줄러(S15P11B209-557)는 여전히 {@code app.notification.retention} 프로퍼티를 기준으로 동작한다. 이 조회
 * API는 사용자별 값을 다루므로 DB를 기준으로 하며, 두 경로의 정합은 수정 API(S15P11B209-565) 이후 범위다.
 */
@Service
@Transactional(readOnly = true)
public class UserDataRetentionPolicyReader {

  private final UserDataRetentionSettingsRepository dataRetentionSettingsRepository;

  /**
   * 보관 정책 조회기를 구성한다.
   *
   * @param dataRetentionSettingsRepository 데이터 보관 설정 읽기 저장소
   */
  public UserDataRetentionPolicyReader(
      UserDataRetentionSettingsRepository dataRetentionSettingsRepository) {
    this.dataRetentionSettingsRepository = dataRetentionSettingsRepository;
  }

  /**
   * 사용자의 데이터 보관 정책을 반환한다.
   *
   * @param userId 조회할 사용자 식별자
   * @return 저장된 보관 정책이며, 저장 행이 없으면 기본값
   */
  public DataRetentionPolicyResponse read(Long userId) {
    return dataRetentionSettingsRepository
        .findByUserId(userId)
        .map(
            projection ->
                DataRetentionPolicyResponse.provisional(
                    projection.getRetentionDays(), projection.getNoticeDaysBefore()))
        .orElseGet(DataRetentionPolicyResponse::defaults);
  }
}
