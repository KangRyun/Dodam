package com.ssafy.b209.child.repository;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.dao.DataRetrievalFailureException;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

/**
 * 아동 프로필과 보호자 관계, 응답 방식을 기존 정규화 Table 구조에 저장한다.
 *
 * <p>하위 Table에는 JPA Entity가 없어 읽기 측과 동일하게 native SQL로 저장하며 절대 경로나 개인정보를 로그에 남기지 않는다.
 */
@Repository
public class ChildRegistrationRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 아동 등록에 필요한 Insert Query를 실행하는 Repository를 생성한다.
   *
   * @param jdbcTemplate 아동 관련 Table에 저장할 JDBC Template
   */
  public ChildRegistrationRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 새 아동 프로필 행을 저장하고 생성된 식별자를 반환한다.
   *
   * <p>Tutorial 상태는 {@code NOT_STARTED}, 프로필 상태는 {@code ACTIVE}로 초기화한다.
   *
   * @param nickname 아동 별칭
   * @param birthDate 아동 생년월일
   * @param questionDifficulty 질문 난이도 Enum 이름
   * @param preferredCharacter 선호 캐릭터, 없으면 {@code null}
   * @param profileImageUrl 프로필 이미지 URL, 없으면 {@code null}
   * @param createdAt 생성 및 수정 시각으로 사용할 기준 시각
   * @return 생성된 아동 식별자
   */
  public long insertChild(
      String nickname,
      LocalDate birthDate,
      String questionDifficulty,
      String preferredCharacter,
      String profileImageUrl,
      LocalDateTime createdAt) {
    KeyHolder keyHolder = new GeneratedKeyHolder();
    jdbcTemplate.update(
        connection -> {
          PreparedStatement statement =
              connection.prepareStatement(
                  """
                  insert into children (
                      nickname, birth_date, question_difficulty, preferred_character,
                      profile_image_url, tutorial_status, profile_status, created_at, updated_at)
                  values (?, ?, ?, ?, ?, 'NOT_STARTED', 'ACTIVE', ?, ?)
                  """,
                  Statement.RETURN_GENERATED_KEYS);
          statement.setString(1, nickname);
          statement.setObject(2, birthDate);
          statement.setString(3, questionDifficulty);
          statement.setString(4, preferredCharacter);
          statement.setString(5, profileImageUrl);
          statement.setObject(6, createdAt);
          statement.setObject(7, createdAt);
          return statement;
        },
        keyHolder);
    Number key = keyHolder.getKey();
    if (key == null) {
      throw new DataRetrievalFailureException("Failed to retrieve generated child id");
    }
    return key.longValue();
  }

  /**
   * 등록 보호자와 아동의 관계를 저장한다.
   *
   * @param guardianUserId 등록을 요청한 보호자 사용자 식별자
   * @param childId 등록된 아동 식별자
   * @param relationshipType 관계 유형 Enum 이름
   */
  public void insertGuardianRelation(long guardianUserId, long childId, String relationshipType) {
    jdbcTemplate.update(
        """
        insert into guardian_child_relations (guardian_user_id, child_id, relationship_type)
        values (?, ?, ?)
        """,
        guardianUserId,
        childId,
        relationshipType);
  }

  /**
   * 아동 응답 방식을 요청 순서대로 0부터 시작하는 표시 순서와 함께 저장한다.
   *
   * @param childId 응답 방식을 저장할 아동 식별자
   * @param responseModes 저장 순서가 유지된 응답 방식 Enum 이름 목록
   */
  public void insertResponseModes(long childId, List<String> responseModes) {
    jdbcTemplate.batchUpdate(
        """
        insert into child_response_modes (child_id, response_mode, display_order)
        values (?, ?, ?)
        """,
        new BatchPreparedStatementSetter() {
          @Override
          public void setValues(PreparedStatement statement, int index) throws SQLException {
            statement.setLong(1, childId);
            statement.setString(2, responseModes.get(index));
            statement.setInt(3, index);
          }

          @Override
          public int getBatchSize() {
            return responseModes.size();
          }
        });
  }

  /**
   * 등록 Transaction에서 연결이 끝난 프로필 이미지 조회 URL을 저장한다.
   *
   * @param childId 등록된 아동 ID
   * @param profileImageUrl 인증 이미지 조회 URL
   * @param updatedAt 변경 시각
   */
  public void updateProfileImageUrl(long childId, String profileImageUrl, LocalDateTime updatedAt) {
    jdbcTemplate.update(
        "update children set profile_image_url = ?, updated_at = ? where id = ?",
        profileImageUrl,
        updatedAt,
        childId);
  }
}
