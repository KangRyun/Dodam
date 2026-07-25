package com.ssafy.b209.user.repository;

import com.ssafy.b209.auth.domain.User;
import java.util.Optional;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 사용자 알림 수신 설정을 읽는 저장소다.
 *
 * <p>{@code user_notification_settings}는 별도 Entity로 매핑하지 않고 읽기 전용 Projection으로만 노출한다. 쓰기 경로(알림 설정
 * 변경 API)는 별도 이슈에서 다룬다.
 */
public interface UserNotificationSettingsRepository extends Repository<User, Long> {

  /**
   * 사용자의 알림 수신 설정을 조회한다.
   *
   * @param userId 조회할 사용자 식별자
   * @return 저장된 알림 설정 Projection, 행이 없으면 빈 값
   */
  @Query(
      value =
          """
          select s.analysis_completed as analysisCompleted,
                 s.community as community,
                 s.service_notice as serviceNotice,
                 s.marketing as marketing
            from user_notification_settings s
           where s.user_id = :userId
          """,
      nativeQuery = true)
  Optional<UserNotificationSettingsProjection> findByUserId(@Param("userId") Long userId);
}
