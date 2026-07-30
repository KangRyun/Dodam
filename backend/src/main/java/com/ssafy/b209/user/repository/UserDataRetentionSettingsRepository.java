package com.ssafy.b209.user.repository;

import com.ssafy.b209.auth.domain.User;
import java.util.Optional;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 사용자별 데이터 보관 설정을 읽는 저장소다.
 *
 * <p>{@code user_data_retention_settings}는 별도 Entity로 매핑하지 않고 읽기 전용 Projection과 Native Query로만
 * 노출한다. {@code user_notification_settings}와 같은 방식이며, 조회 경로에서 보관 설정을 변경할 수 없게 하려는 의도다. 쓰기는
 * S15P11B209-565가 소유한다.
 */
public interface UserDataRetentionSettingsRepository extends Repository<User, Long> {

  /**
   * 사용자의 데이터 보관 설정을 조회한다.
   *
   * @param userId 조회할 사용자 식별자
   * @return 저장된 보관 설정 Projection, 행이 없으면 빈 값
   */
  @Query(
      value =
          """
          select s.retention_days as retentionDays,
                 s.notice_days_before as noticeDaysBefore
            from user_data_retention_settings s
           where s.user_id = :userId
          """,
      nativeQuery = true)
  Optional<UserDataRetentionSettingsProjection> findByUserId(@Param("userId") Long userId);
}
