package com.ssafy.b209.conversation.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 대화와 연결된 활성 아동에 대한 보호자의 접근 권한만 조회하는 저장소다. */
@Repository
public class ConversationEndAuthorizationRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 대화 종료 전 접근 권한을 조회할 저장소를 구성한다.
   *
   * @param jdbcTemplate 관계 존재 여부를 조회하는 JDBC 템플릿
   */
  public ConversationEndAuthorizationRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 보호자가 지정한 대화의 활성·미삭제 아동에 접근할 수 있는지 확인한다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param conversationId 접근 대상 대화 세션 식별자
   * @return 대화, 그림 세션, 활성 아동 및 보호자 관계가 모두 존재하면 {@code true}
   */
  public boolean hasConversationAccess(Long guardianUserId, Long conversationId) {
    Boolean exists =
        jdbcTemplate.queryForObject(
            """
            select exists(
              select 1
                from conversation_sessions conversation
                join drawing_sessions drawing on drawing.id = conversation.drawing_session_id
                join children child on child.id = drawing.child_id
                join guardian_child_relations relation on relation.child_id = child.id
               where relation.guardian_user_id = ?
                 and conversation.id = ?
                 and drawing.session_status <> 'DELETED'
                 and drawing.deleted_at is null
                 and child.profile_status = 'ACTIVE'
                 and child.deleted_at is null
            )
            """,
            Boolean.class,
            guardianUserId,
            conversationId);
    return Boolean.TRUE.equals(exists);
  }
}
