package com.ssafy.b209.user.repository;

import com.ssafy.b209.auth.domain.User;
import java.util.Optional;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 사용자별 데이터 보관 설정을 읽고 쓰는 저장소다.
 *
 * <p>{@code user_data_retention_settings}는 별도 Entity로 매핑하지 않고 읽기 전용 Projection과 Native Query로 노출한다.
 * 쓰기는 {@code INSERT ... ON DUPLICATE KEY UPDATE} 한 문장으로 처리해 동시 요청에서도 {@code user_id} 단일 행이 유지되도록
 * DB의 PK 충돌 처리에 원자성을 위임한다.
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

  /**
   * 사용자의 데이터 보관 설정을 전달받은 두 값으로 저장한다.
   *
   * <p>설정 행이 없으면 INSERT, 있으면 두 기간 컬럼을 UPDATE하는 upsert다. {@code user_id}가 PK이므로 동시 요청이 겹쳐도 중복 INSERT
   * 대신 {@code ON DUPLICATE KEY UPDATE} 경로로 수렴한다. {@code updated_at}은 컬럼의 {@code ON UPDATE
   * CURRENT_TIMESTAMP} 정의로 UPDATE 시 자동 갱신된다.
   *
   * @param userId 대상 사용자 식별자
   * @param retentionDays 데이터 보관 기간(일)
   * @param noticeDaysBefore 보관 만료 사전 안내 시점(일)
   */
  @Modifying
  @Query(
      value =
          """
          insert into user_data_retention_settings
                 (user_id, retention_days, notice_days_before)
          values (:userId, :retentionDays, :noticeDaysBefore)
          on duplicate key update
                 retention_days = values(retention_days),
                 notice_days_before = values(notice_days_before)
          """,
      nativeQuery = true)
  void upsert(
      @Param("userId") Long userId,
      @Param("retentionDays") int retentionDays,
      @Param("noticeDaysBefore") int noticeDaysBefore);
}
