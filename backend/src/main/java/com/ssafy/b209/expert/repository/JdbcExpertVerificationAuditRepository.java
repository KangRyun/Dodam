package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

/** 정규화된 전문가 검토 이력과 공통 감사 로그를 JDBC로 저장한다. */
@Repository
public class JdbcExpertVerificationAuditRepository implements ExpertVerificationAuditRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 전문가 검토 이력 저장소를 구성한다.
   *
   * @param jdbcTemplate 검토 이력 저장용 JDBC 도구
   */
  public JdbcExpertVerificationAuditRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  @Override
  public void saveReview(
      Long reviewerUserId,
      Long expertId,
      ExpertVerificationStatus status,
      List<Long> verifiedCredentialIds,
      String rejectionReason,
      String internalNote,
      LocalDateTime reviewedAt) {
    GeneratedKeyHolder keyHolder = new GeneratedKeyHolder();
    jdbcTemplate.update(
        connection -> {
          PreparedStatement statement =
              connection.prepareStatement(
                  """
                  INSERT INTO expert_verification_reviews
                      (expert_profile_id, reviewer_user_id, decision_status,
                       rejection_reason, internal_note, reviewed_at)
                  VALUES (?, ?, ?, ?, ?, ?)
                  """,
                  Statement.RETURN_GENERATED_KEYS);
          statement.setLong(1, expertId);
          statement.setLong(2, reviewerUserId);
          statement.setString(3, status.name());
          statement.setString(4, rejectionReason);
          statement.setString(5, internalNote);
          statement.setObject(6, reviewedAt);
          return statement;
        },
        keyHolder);
    Long reviewId = Objects.requireNonNull(keyHolder.getKey()).longValue();
    for (Long credentialId : verifiedCredentialIds) {
      jdbcTemplate.update(
          "INSERT INTO expert_verification_review_credentials "
              + "(review_id, expert_credential_id) VALUES (?, ?)",
          reviewId,
          credentialId);
    }
    jdbcTemplate.update(
        """
        INSERT INTO audit_logs
            (actor_user_id, action_type, resource_type, resource_id, created_at)
        VALUES (?, 'EXPERT_VERIFICATION_REVIEWED', 'EXPERT_PROFILE', ?, ?)
        """,
        reviewerUserId,
        expertId,
        reviewedAt);
  }
}
