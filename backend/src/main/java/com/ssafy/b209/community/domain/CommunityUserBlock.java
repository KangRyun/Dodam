package com.ssafy.b209.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;

/**
 * 사용자별 커뮤니티 차단 관계의 영속 스키마를 표현한다.
 *
 * <p>쓰기 연산은 MySQL의 원자적 멱등 처리를 위해 전용 JDBC 저장소가 담당한다. 이 매핑은 JPA 기반 테스트 스키마와 운영 Flyway 스키마의 구조를 일치시키기
 * 위해 유지한다.
 */
@Entity
@Table(
    name = "user_blocks",
    uniqueConstraints =
        @UniqueConstraint(
            name = "uk_user_blocks_blocker_blocked",
            columnNames = {"blocker_user_id", "blocked_user_id"}))
public class CommunityUserBlock {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "blocker_user_id", nullable = false)
  private Long blockerUserId;

  @Column(name = "blocked_user_id", nullable = false)
  private Long blockedUserId;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 차단 관계를 복원할 때 사용한다. */
  protected CommunityUserBlock() {}
}
