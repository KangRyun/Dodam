package com.ssafy.b209.notification.repository;

import java.time.LocalDateTime;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 보관 만료가 임박한 데이터의 소유 보호자를 개인정보 조회 없이 찾는다.
 *
 * <p>전용 보관·삭제예정 컬럼이 스키마에 없어(보관 정책 S15P11B209-564·565 미확정) <b>소프트 삭제된 아동의 {@code deleted_at}</b>을 보관
 * 시작 시점으로 보는 임시 기준을 채택했다. 즉 삭제된 아동 데이터는 일정 보관 기간이 지나면 영구 삭제된다는 가정 아래, 그 만료가 임박한 아동의 보호자를 안내 대상으로
 * 본다(557 as-built §보관 만료 기준). 이 기준은 임시이며, 이 저장소를 부르는 스케줄러는 기본적으로 꺼져 있다.
 */
@Repository
public class RetentionExpiryRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 보관 만료 대상 Query를 실행할 JDBC Template을 주입받는다.
   *
   * @param jdbcTemplate 보관 만료 대상 조회용 JDBC Template
   */
  public RetentionExpiryRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 삭제 시각이 기준일 이전인 아동의 보호자 사용자 ID를 찾는다.
   *
   * <p>보관 시작 시각({@code deleted_at})이 만료 임박 기준일 이하인 아동만 남기고 그 보호자를 중복 없이 반환한다. 대상이 없으면 빈 목록을 반환한다.
   *
   * @param deletedAtCutoff 이 시각 이전에 삭제된 아동을 만료 임박으로 판정하는 기준일
   * @param limit 한 번에 조회할 최대 보호자 수
   * @return 보관 만료 임박 데이터의 소유 보호자 사용자 ID 목록이며 대상이 없으면 빈 목록
   */
  public List<Long> findExpiringDataOwnerUserIds(LocalDateTime deletedAtCutoff, int limit) {
    return jdbcTemplate.queryForList(
        """
        select distinct relation.guardian_user_id
          from children child
          join guardian_child_relations relation on relation.child_id = child.id
         where child.deleted_at is not null
           and child.deleted_at <= ?
         order by relation.guardian_user_id
         limit ?
        """,
        Long.class,
        deletedAtCutoff,
        limit);
  }
}
