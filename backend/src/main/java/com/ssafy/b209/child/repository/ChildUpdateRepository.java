package com.ssafy.b209.child.repository;

import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 정규화된 아동 프로필, 보호자 관계와 응답 방식 Table의 변경 Query를 담당한다.
 *
 * <p>호출 Service의 Transaction 안에서 아동 행을 잠근 뒤 관련 Table을 함께 변경한다.
 */
@Repository
public class ChildUpdateRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 아동 프로필 변경에 사용할 Repository를 생성한다.
   *
   * @param jdbcTemplate 아동 관련 Table을 변경할 JDBC Template
   */
  public ChildUpdateRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 요청 보호자에게 연결된 활성 아동 행을 쓰기 잠금으로 조회한다.
   *
   * @param guardianUserId 변경을 요청한 보호자 사용자 식별자
   * @param childId 변경할 아동 식별자
   * @return 변경 가능한 아동이면 {@code true}
   */
  public boolean lockAccessibleChild(long guardianUserId, long childId) {
    return !jdbcTemplate
        .queryForList(
            """
            select c.id
              from children c
              join guardian_child_relations relation on relation.child_id = c.id
             where c.id = ?
               and relation.guardian_user_id = ?
               and c.deleted_at is null
               and c.profile_status = 'ACTIVE'
             for update
            """,
            Long.class,
            childId,
            guardianUserId)
        .isEmpty();
  }

  /**
   * 잠긴 아동 행의 현재 Tutorial 상태를 조회한다.
   *
   * @param childId 상태를 조회할 아동 식별자
   * @return 현재 Tutorial 상태
   */
  public ChildTutorialStatus findTutorialStatus(long childId) {
    String status =
        jdbcTemplate.queryForObject(
            "select tutorial_status from children where id = ?", String.class, childId);
    return ChildTutorialStatus.valueOf(status);
  }

  /**
   * 아동 Tutorial 상태와 복원 정보를 변경한다.
   *
   * @param childId 변경할 아동 식별자
   * @param tutorialStatus 변경할 Tutorial 상태
   * @param lastStep 마지막 단계, 기존 값을 유지하려면 {@code null}
   * @param completedAt 완료 또는 건너뛰기 시각, 진행 중이면 {@code null}
   * @param updatedAt 변경 시각
   */
  public void updateTutorialProgress(
      long childId,
      ChildTutorialStatus tutorialStatus,
      String lastStep,
      LocalDateTime completedAt,
      LocalDateTime updatedAt) {
    jdbcTemplate.update(
        """
        update children
           set tutorial_status = ?,
               tutorial_last_step = coalesce(?, tutorial_last_step),
               tutorial_completed_at = ?,
               updated_at = ?
         where id = ?
        """,
        tutorialStatus.name(),
        lastStep,
        completedAt,
        updatedAt,
        childId);
  }

  /**
   * 전달된 아동 기본 정보만 변경하고 수정 시각을 갱신한다.
   *
   * @param childId 변경할 아동 식별자
   * @param nickname 변경할 별칭, 유지하려면 {@code null}
   * @param birthDate 변경할 생년월일, 유지하려면 {@code null}
   * @param preferredCharacter 변경할 선호 캐릭터, 유지하려면 {@code null}
   * @param questionDifficulty 변경할 질문 난이도, 유지하려면 {@code null}
   * @param updatedAt 수정 시각
   */
  public void updateProfile(
      long childId,
      String nickname,
      LocalDate birthDate,
      String preferredCharacter,
      QuestionDifficulty questionDifficulty,
      LocalDateTime updatedAt) {
    jdbcTemplate.update(
        """
        update children
           set nickname = coalesce(?, nickname),
               birth_date = coalesce(?, birth_date),
               preferred_character = coalesce(?, preferred_character),
               question_difficulty = coalesce(?, question_difficulty),
               updated_at = ?
         where id = ?
        """,
        nickname,
        birthDate,
        preferredCharacter,
        questionDifficulty == null ? null : questionDifficulty.name(),
        updatedAt,
        childId);
  }

  /**
   * 아동 프로필 이미지 조회 URL을 명시된 값으로 교체한다.
   *
   * @param childId 변경할 아동 ID
   * @param profileImageUrl 새 조회 URL, 기존 이미지를 제거하는 경우 {@code null}
   * @param updatedAt 변경 시각
   */
  public void updateProfileImageUrl(long childId, String profileImageUrl, LocalDateTime updatedAt) {
    jdbcTemplate.update(
        "update children set profile_image_url = ?, updated_at = ? where id = ?",
        profileImageUrl,
        updatedAt,
        childId);
  }

  /**
   * 선호 캐릭터를 명시된 코드로 교체하거나 선택을 해제한다.
   *
   * @param childId 변경할 아동 ID
   * @param preferredCharacter 새 캐릭터 코드, 선택 해제 시 {@code null}
   * @param updatedAt 변경 시각
   */
  public void updatePreferredCharacter(
      long childId, String preferredCharacter, LocalDateTime updatedAt) {
    jdbcTemplate.update(
        "update children set preferred_character = ?, updated_at = ? where id = ?",
        preferredCharacter,
        updatedAt,
        childId);
  }

  /**
   * 현재 요청 보호자와 아동의 관계 유형을 변경한다.
   *
   * @param guardianUserId 관계를 변경할 보호자 사용자 식별자
   * @param childId 관계 대상 아동 식별자
   * @param relationshipType 변경할 관계 유형
   */
  public void updateRelationship(
      long guardianUserId, long childId, GuardianRelationshipType relationshipType) {
    jdbcTemplate.update(
        """
        update guardian_child_relations
           set relationship_type = ?
         where guardian_user_id = ?
           and child_id = ?
        """,
        relationshipType.name(),
        guardianUserId,
        childId);
  }

  /**
   * 아동의 응답 방식 목록을 요청 순서대로 교체한다.
   *
   * @param childId 변경할 아동 식별자
   * @param responseModes 중복이 제거된 응답 방식 목록
   */
  public void replaceResponseModes(long childId, List<ResponseMode> responseModes) {
    jdbcTemplate.update("delete from child_response_modes where child_id = ?", childId);
    List<Object[]> rows =
        java.util.stream.IntStream.range(0, responseModes.size())
            .mapToObj(index -> new Object[] {childId, responseModes.get(index).name(), index})
            .toList();
    jdbcTemplate.batchUpdate(
        """
        insert into child_response_modes (child_id, response_mode, display_order)
        values (?, ?, ?)
        """,
        rows);
  }
}
