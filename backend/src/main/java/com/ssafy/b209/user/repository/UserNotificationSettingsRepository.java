package com.ssafy.b209.user.repository;

import com.ssafy.b209.auth.domain.User;
import java.util.Optional;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 사용자 알림 수신 설정을 읽고 쓰는 저장소다.
 *
 * <p>{@code user_notification_settings}는 별도 Entity로 매핑하지 않고 읽기 전용 Projection과 Native Query로만 노출한다.
 * 쓰기는 행 존재 여부를 애플리케이션에서 분기하지 않고 {@code INSERT ... ON DUPLICATE KEY UPDATE} 한 문장으로 처리해, 동시 요청에서도
 * {@code user_id} 단일 행이 유지되도록 DB의 PK 충돌 처리에 원자성을 위임한다.
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

  /**
   * 사용자의 알림 수신 설정을 전달받은 네 값으로 저장한다.
   *
   * <p>설정 행이 없으면 INSERT, 있으면 네 컬럼을 UPDATE하는 upsert다. {@code user_id}가 PK이므로 동시 요청이 겹쳐도 중복 INSERT 대신
   * {@code ON DUPLICATE KEY UPDATE} 경로로 수렴해 행이 하나로 유지된다. {@code updated_at}은 컬럼의 {@code ON UPDATE
   * CURRENT_TIMESTAMP} 정의로 UPDATE 시 자동 갱신된다.
   *
   * @param userId 대상 사용자 식별자
   * @param analysisCompleted 분석 완료 알림 수신 여부
   * @param community 커뮤니티 알림 수신 여부
   * @param serviceNotice 서비스 공지 수신 여부
   * @param marketing 마케팅 알림 수신 여부
   */
  @Modifying
  @Query(
      value =
          """
          insert into user_notification_settings
                 (user_id, analysis_completed, community, service_notice, marketing)
          values (:userId, :analysisCompleted, :community, :serviceNotice, :marketing)
          on duplicate key update
                 analysis_completed = values(analysis_completed),
                 community = values(community),
                 service_notice = values(service_notice),
                 marketing = values(marketing)
          """,
      nativeQuery = true)
  void upsert(
      @Param("userId") Long userId,
      @Param("analysisCompleted") boolean analysisCompleted,
      @Param("community") boolean community,
      @Param("serviceNotice") boolean serviceNotice,
      @Param("marketing") boolean marketing);
}
